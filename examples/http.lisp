; http.lisp -- HTTP and HTTPS: http-get, http-request and their responses
;
; (http-get url) fetches a page and answers a response: read it with
; http-status, http-header (by name, in any case), http-headers and http-body.
; (http-request method url headers body timeout) sends anything else, such as a
; POST with a JSON body. HTTPS works the same way, and certificates are always
; checked against the system's trust store. A 404 is an ordinary response; not
; reaching the host, a timeout or a rejected certificate is an error whose
; message starts with "http:". Requests are made by the system's curl, which
; cog-lisp finds and runs itself: on Linux it must be installed.
;
; So that it runs without the internet, this example first starts a small web
; server of its own, through Smalltalk (Pharo's ZnServer), and talks to that.

(define (serve request)
  (let ((path [[request uri] path]))
    (if (equal? path "weather")
        [(smalltalk ZnResponse) ok: [(smalltalk ZnEntity)
                                      with: "{\"city\": \"Berlin\", \"temperature\": 3.5}"
                                      type: "application/json"]]
        [(smalltalk ZnResponse) notFound: [request uri]])))

(define server
  (let loop ()
    (let ((s [(smalltalk ZnServer) on: (+ 30000 [20000 atRandom])]))
      [s bindingAddress: [(smalltalk NetNameResolver) addressFromString: "127.0.0.1"]]
      [s delegate: [(smalltalk ZnValueDelegate) with: (procedure->block serve)]]
      (if (guard (e (#t #f)) [s start] #t) s (loop)))))

(define base (string-append "http://127.0.0.1:" (number->string [server port]) "/"))

(define r (http-get (string-append base "weather")))
(display (http-status r)) (newline)
(display (http-header r "Content-Type")) (newline)
(let ((data (json-read (http-body r))))
  (display (hash-table-ref data "city")) (display ": ")
  (display (hash-table-ref data "temperature")) (newline))

(display (http-status (http-get (string-append base "nowhere")))) (newline)

; nothing listens on port 1, so this request fails, as a condition
(display (guard (e (#t (error-object-message e)))
           (http-get "http://127.0.0.1:1/")))
(newline)

[server stop]
