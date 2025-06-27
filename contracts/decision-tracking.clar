;; Decision Tracking Contract
;; Records and tracks board decisions

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_ALREADY_VOTED (err u302))
(define-constant ERR_VOTING_ENDED (err u303))

;; Data Variables
(define-data-var next-decision-id uint u1)

;; Data Maps
(define-map decisions
  { decision-id: uint }
  {
    title: (string-ascii 200),
    description: (string-ascii 1000),
    proposer: principal,
    voting-deadline: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    created-at: uint
  }
)

(define-map votes
  { decision-id: uint, voter: principal }
  {
    vote: bool,
    voted-at: uint
  }
)

;; Public Functions

;; Propose a new decision
(define-public (propose-decision
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (voting-deadline uint)
)
  (let ((decision-id (var-get next-decision-id)))
    (map-set decisions
      { decision-id: decision-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        voting-deadline: voting-deadline,
        status: "active",
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        created-at: block-height
      }
    )
    (var-set next-decision-id (+ decision-id u1))
    (ok decision-id)
  )
)

;; Cast a vote
(define-public (cast-vote (decision-id uint) (vote bool))
  (match (map-get? decisions { decision-id: decision-id })
    decision-data
    (begin
      (asserts! (< block-height (get voting-deadline decision-data)) ERR_VOTING_ENDED)
      (asserts! (is-eq (get status decision-data) "active") ERR_VOTING_ENDED)
      (asserts! (is-none (map-get? votes { decision-id: decision-id, voter: tx-sender })) ERR_ALREADY_VOTED)

      (map-set votes
        { decision-id: decision-id, voter: tx-sender }
        {
          vote: vote,
          voted-at: block-height
        }
      )

      (let (
        (new-votes-for (if vote (+ (get votes-for decision-data) u1) (get votes-for decision-data)))
        (new-votes-against (if vote (get votes-against decision-data) (+ (get votes-against decision-data) u1)))
        (new-total-votes (+ (get total-votes decision-data) u1))
      )
        (map-set decisions
          { decision-id: decision-id }
          (merge decision-data {
            votes-for: new-votes-for,
            votes-against: new-votes-against,
            total-votes: new-total-votes
          })
        )
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Finalize decision (only proposer or contract owner)
(define-public (finalize-decision (decision-id uint))
  (match (map-get? decisions { decision-id: decision-id })
    decision-data
    (begin
      (asserts! (or (is-eq tx-sender (get proposer decision-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status decision-data) "active") ERR_VOTING_ENDED)

      (let (
        (final-status (if (> (get votes-for decision-data) (get votes-against decision-data)) "approved" "rejected"))
      )
        (map-set decisions
          { decision-id: decision-id }
          (merge decision-data { status: final-status })
        )
        (ok final-status)
      )
    )
    ERR_NOT_FOUND
  )
)

;; Read-only Functions

;; Get decision information
(define-read-only (get-decision (decision-id uint))
  (map-get? decisions { decision-id: decision-id })
)

;; Get vote information
(define-read-only (get-vote (decision-id uint) (voter principal))
  (map-get? votes { decision-id: decision-id, voter: voter })
)

;; Check if user has voted
(define-read-only (has-voted (decision-id uint) (voter principal))
  (is-some (map-get? votes { decision-id: decision-id, voter: voter }))
)

;; Get total decisions count
(define-read-only (get-total-decisions)
  (- (var-get next-decision-id) u1)
)

;; Get decision result
(define-read-only (get-decision-result (decision-id uint))
  (match (map-get? decisions { decision-id: decision-id })
    decision-data
    (some {
      status: (get status decision-data),
      votes-for: (get votes-for decision-data),
      votes-against: (get votes-against decision-data),
      total-votes: (get total-votes decision-data)
    })
    none
  )
)
