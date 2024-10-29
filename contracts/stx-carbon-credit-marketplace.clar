;; Carbon Credit Marketplace (Enhanced)
;; Allows businesses to trade tokenized carbon credits with improved data validation

;; Define constants for contract ownership and common error messages
(define-constant contract-owner tx-sender) ;; The creator/owner of the contract
(define-constant err-owner-only (err u100)) ;; Error if the action is not performed by the contract owner
(define-constant err-insufficient-balance (err u101)) ;; Error if a user has insufficient credit balance
(define-constant err-invalid-price (err u102)) ;; Error if the price provided is invalid
(define-constant err-listing-not-found (err u103)) ;; Error if a listing ID does not exist
(define-constant err-unauthorized (err u104)) ;; Error if an action is unauthorized
(define-constant err-invalid-metadata (err u105)) ;; Error for invalid credit metadata inputs
(define-constant err-invalid-vintage-year (err u106)) ;; Error for an invalid vintage year
(define-constant err-invalid-verification-standard (err u107)) ;; Error for invalid verification standard input
(define-constant err-invalid-project-type (err u108)) ;; Error for an invalid project type
(define-constant err-listing-already-active (err u109)) ;; Error if a listing is already active
(define-constant err-listing-not-active (err u110)) ;; Error if a listing is not active


;; Data Structures
;; Maps and data variables to store carbon credits, listings, and unique identifiers

;; Mapping credit balances for each owner
(define-map credit-balances { owner: principal } { amount: uint })

;; Mapping metadata associated with each credit type
(define-map credit-metadata 
  { credit-id: uint } 
  { 
    issuer: principal,  ;; The principal who issued the credit
    vintage-year: uint, ;; The year the carbon credit is associated with
    verification-standard: (string-ascii 64), ;; Verification standard name (e.g., "Gold Standard")
    project-type: (string-ascii 64), ;; Type of project generating the credits (e.g., "Reforestation")
    amount: uint ;; Total amount of credits issued in this ID
  }
)

;; Map for listing active credit sales
(define-map listings 
  { listing-id: uint } 
  {
    seller: principal, ;; Principal who owns the credits and created the listing
    credit-id: uint, ;; ID of the carbon credit being listed
    amount: uint, ;; Amount of credits available in the listing
    price-per-credit: uint, ;; Sale price per credit
    active: bool ;; Status of the listing, true if active
  }
)

;; Data variables to keep track of unique credit and listing IDs
(define-data-var next-credit-id uint u1) ;; Incremental ID for each new credit type
(define-data-var next-listing-id uint u1) ;; Incremental ID for each new listing


;; Read-only functions
;; These functions retrieve data without modifying the state of the contract

;; Returns the credit balance of a given principal
(define-read-only (get-balance (owner principal))
  (default-to { amount: u0 }
    (map-get? credit-balances { owner: owner }))
)

;; Retrieves credit metadata by its unique ID
(define-read-only (get-credit-info (credit-id uint))
  (map-get? credit-metadata { credit-id: credit-id })
)

;; Fetches listing details for a given listing ID
(define-read-only (get-listing (listing-id uint))
  (map-get? listings { listing-id: listing-id })
)


;; Public functions

;; Function to create a new listing for selling credits
(define-public (create-listing (credit-id uint) 
                             (amount uint) 
                             (price-per-credit uint))
  (let (
    (listing-id (var-get next-listing-id))
    (seller-balance (get amount (get-balance tx-sender)))
  )
    ;; Validate inputs and balances
    (asserts! (> amount u0) err-invalid-metadata)
    (asserts! (> price-per-credit u0) err-invalid-price)
    (asserts! (>= seller-balance amount) err-insufficient-balance)
    (asserts! (is-some (get-credit-info credit-id)) err-invalid-metadata)

    ;; Create a new active listing with the provided data
    (map-set listings
      { listing-id: listing-id }
      {
        seller: tx-sender,
        credit-id: credit-id,
        amount: amount,
        price-per-credit: price-per-credit,
        active: true
      }
    )
    ;; Increment the listing ID for the next listing
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

;; Function to cancel a listing
(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (get-listing listing-id) err-listing-not-found)))
    ;; Ensure only the seller can cancel their own listing
    (asserts! (is-eq tx-sender (get seller listing)) err-unauthorized)
    ;; Ensure listing is active before cancellation
    (asserts! (get active listing) err-listing-not-found)

    ;; Mark the listing as inactive
    (map-set listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    (ok true)
  )
)

;; Function for users to purchase credits from a listing
(define-public (purchase-credits (listing-id uint))
  (let (
    (listing (unwrap! (get-listing listing-id) err-listing-not-found))
    (total-price (* (get price-per-credit listing) (get amount listing)))
  )
    ;; Ensure the listing is active before purchase
    (asserts! (get active listing) err-listing-not-found)

    ;; Transfer STX from buyer to seller
    (try! (stx-transfer? total-price tx-sender (get seller listing)))

    ;; Update balances for seller and buyer
    (map-set credit-balances
      { owner: (get seller listing) }
      { amount: (- (get amount (get-balance (get seller listing))) (get amount listing)) }
    )
    (map-set credit-balances
      { owner: tx-sender }
      { amount: (+ (get amount (get-balance tx-sender)) (get amount listing)) }
    )

    ;; Mark listing as inactive after purchase
    (map-set listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    (ok true)
  )
)
