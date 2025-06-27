;; Compliance Monitoring Contract
;; Monitors governance compliance requirements

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_NOT_FOUND (err u401))
(define-constant ERR_ALREADY_EXISTS (err u402))

;; Data Variables
(define-data-var next-rule-id uint u1)
(define-data-var next-violation-id uint u1)

;; Data Maps
(define-map compliance-rules
  { rule-id: uint }
  {
    title: (string-ascii 200),
    description: (string-ascii 500),
    category: (string-ascii 50),
    severity: (string-ascii 20),
    active: bool,
    created-at: uint,
    created-by: principal
  }
)

(define-map violations
  { violation-id: uint }
  {
    rule-id: uint,
    violator: principal,
    description: (string-ascii 500),
    severity: (string-ascii 20),
    status: (string-ascii 20),
    reported-at: uint,
    reported-by: principal,
    resolved-at: (optional uint)
  }
)

(define-map compliance-status
  { entity: principal }
  {
    total-violations: uint,
    active-violations: uint,
    last-violation: (optional uint),
    compliance-score: uint
  }
)

;; Public Functions

;; Add compliance rule (only contract owner)
(define-public (add-compliance-rule
  (title (string-ascii 200))
  (description (string-ascii 500))
  (category (string-ascii 50))
  (severity (string-ascii 20))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (let ((rule-id (var-get next-rule-id)))
      (map-set compliance-rules
        { rule-id: rule-id }
        {
          title: title,
          description: description,
          category: category,
          severity: severity,
          active: true,
          created-at: block-height,
          created-by: tx-sender
        }
      )
      (var-set next-rule-id (+ rule-id u1))
      (ok rule-id)
    )
  )
)

;; Report violation
(define-public (report-violation
  (rule-id uint)
  (violator principal)
  (description (string-ascii 500))
)
  (match (map-get? compliance-rules { rule-id: rule-id })
    rule-data
    (begin
      (asserts! (get active rule-data) ERR_NOT_FOUND)
      (let ((violation-id (var-get next-violation-id)))
        (map-set violations
          { violation-id: violation-id }
          {
            rule-id: rule-id,
            violator: violator,
            description: description,
            severity: (get severity rule-data),
            status: "open",
            reported-at: block-height,
            reported-by: tx-sender,
            resolved-at: none
          }
        )

        ;; Update compliance status
        (match (map-get? compliance-status { entity: violator })
          status-data
          (map-set compliance-status
            { entity: violator }
            {
              total-violations: (+ (get total-violations status-data) u1),
              active-violations: (+ (get active-violations status-data) u1),
              last-violation: (some violation-id),
              compliance-score: (if (> (get compliance-score status-data) u10) (- (get compliance-score status-data) u10) u0)
            }
          )
          (map-set compliance-status
            { entity: violator }
            {
              total-violations: u1,
              active-violations: u1,
              last-violation: (some violation-id),
              compliance-score: u90
            }
          )
        )

        (var-set next-violation-id (+ violation-id u1))
        (ok violation-id)
      )
    )
    ERR_NOT_FOUND
  )
)

;; Resolve violation (only contract owner)
(define-public (resolve-violation (violation-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (map-get? violations { violation-id: violation-id })
      violation-data
      (begin
        (map-set violations
          { violation-id: violation-id }
          (merge violation-data {
            status: "resolved",
            resolved-at: (some block-height)
          })
        )

        ;; Update compliance status
        (let ((violator (get violator violation-data)))
          (match (map-get? compliance-status { entity: violator })
            status-data
            (map-set compliance-status
              { entity: violator }
              (merge status-data {
                active-violations: (if (> (get active-violations status-data) u0) (- (get active-violations status-data) u1) u0),
                compliance-score: (if (< (get compliance-score status-data) u95) (+ (get compliance-score status-data) u5) u100)
              })
            )
            false
          )
        )
        (ok true)
      )
      ERR_NOT_FOUND
    )
  )
)

;; Toggle rule status (only contract owner)
(define-public (toggle-rule-status (rule-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (map-get? compliance-rules { rule-id: rule-id })
      rule-data
      (begin
        (map-set compliance-rules
          { rule-id: rule-id }
          (merge rule-data { active: (not (get active rule-data)) })
        )
        (ok true)
      )
      ERR_NOT_FOUND
    )
  )
)

;; Read-only Functions

;; Get compliance rule
(define-read-only (get-compliance-rule (rule-id uint))
  (map-get? compliance-rules { rule-id: rule-id })
)

;; Get violation
(define-read-only (get-violation (violation-id uint))
  (map-get? violations { violation-id: violation-id })
)

;; Get compliance status
(define-read-only (get-compliance-status (entity principal))
  (default-to
    { total-violations: u0, active-violations: u0, last-violation: none, compliance-score: u100 }
    (map-get? compliance-status { entity: entity })
  )
)

;; Get total rules count
(define-read-only (get-total-rules)
  (- (var-get next-rule-id) u1)
)

;; Get total violations count
(define-read-only (get-total-violations)
  (- (var-get next-violation-id) u1)
)
