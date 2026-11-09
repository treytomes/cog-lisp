;;; http.lisp -- http-request and http-get against a local server in this image
;;; (specs/https-and-json.md R-7, R-8, R-12; AC-3). The server is Pharo's
;;; ZnServer on 127.0.0.1, handled by a LISP procedure: the wait for curl polls,
;;; so the server runs while a request is made. No check needs the internet.
(load "../../lib/test.lisp")

(define (text-response code type text)
  (let ((r [(smalltalk ZnResponse) statusLine: [(smalltalk ZnStatusLine) code: code]]))
    [r entity: [(smalltalk ZnEntity) with: text type: type]]
    r))

(define (bytes-response type bytes)
  (let ((r [(smalltalk ZnResponse) ok: [(smalltalk ZnEntity) with: bytes type: type]]))
    r))

(define (handle request)
  (let ((path [[request uri] path]))
    (cond
      ((equal? path "hello")
       (let ((r (text-response 200 "text/plain; charset=utf-8" "hello, λ")))
         [[r headers] at: "X-Custom" put: "yes"]
         r))
      ((equal? path "echo")
       (let ((entity [request entity]))
         (text-response 200 "text/plain; charset=utf-8"
                        (string-append [[request method] asString] "|"
                                       (let ((h [[request headers] at: "X-Test" ifAbsent: (procedure->block (lambda () "none"))])) h)
                                       "|"
                                       (if (smalltalk-nil? entity) "" [entity contents])))))
      ((equal? path "query")
       (text-response 200 "text/plain; charset=utf-8" [[request uri] queryAt: "q"]))
      ((equal? path "type")
       (text-response 200 "text/plain" [[request headers] at: "Content-Type" ifAbsent: (procedure->block (lambda () "none"))]))
      ((equal? path "redirect")
       [(smalltalk ZnResponse) redirect: "/hello"])
      ((equal? path "latin1")
       (bytes-response "text/plain; charset=iso-8859-1" [(smalltalk ByteArray) with: 99 with: 97 with: 102 with: 233]))
      ((equal? path "teapot")
       (text-response 418 "text/plain" "short and stout"))
      ((equal? path "slow")
       [[(smalltalk Delay) forSeconds: 3] wait]
       (text-response 200 "text/plain" "late"))
      (else [(smalltalk ZnResponse) notFound: [request uri]]))))

;; a server on a free port of 127.0.0.1
(define (start-server)
  (let loop ((tries 0))
    (let* ((port (+ 30000 [20000 atRandom]))
           (server [(smalltalk ZnServer) on: port]))
      [server bindingAddress: [(smalltalk NetNameResolver) addressFromString: "127.0.0.1"]]
      [server delegate: [(smalltalk ZnValueDelegate) with: (procedure->block handle)]]
      (if (guard (e (#t #f)) [server start] #t)
          (cons server port)
          (if (< tries 10) (loop (+ tries 1)) (error "no free port for the test server"))))))

(define server+port (start-server))
(define base (string-append "http://127.0.0.1:" (number->string (cdr server+port)) "/"))
(define (url path) (string-append base path))

(define-test "a GET answers its status, headers and body (AC-3)"
  (let ((r (http-get (url "hello"))))
    (check-true (http-response? r))
    (check (http-status r) 200)
    (check (http-body r) "hello, λ")
    (check (http-header r "x-custom") "yes")
    (check (http-header r "X-CUSTOM") "yes")               ; any case
    (check (http-header r "no-such-header") #f)
    (check-true (string? (cdr (assoc "content-type" (http-headers r)))))
    (check-written r "#<http-response 200>")))

(define-test "a POST sends its body and headers, as given"
  (let ((r (http-request 'POST (url "echo") '(("X-Test" . "a b'c\"d $HOME;x")) "{\"k\": \"é\"}")))
    (check (http-status r) 200)
    (check (http-body r) "POST|a b'c\"d $HOME;x|{\"k\": \"é\"}"))
  (check (http-body (http-request "put" (url "echo") '() "x")) "PUT|none|x"))

(define-test "a body is sent as UTF-8 text unless a Content-Type is given"
  (check (http-body (http-request 'POST (url "type") '() "x")) "text/plain; charset=utf-8")
  (check (http-body (http-request 'POST (url "type") '(("content-type" . "application/json")) "{}"))
         "application/json"))

(define-test "4xx and 5xx are responses, not errors"
  (check (http-status (http-get (url "missing"))) 404)
  (let ((r (http-get (url "teapot"))))
    (check (http-status r) 418)
    (check (http-body r) "short and stout")))

(define-test "a redirect is followed; the headers are the last response's"
  (let ((r (http-get (url "redirect"))))
    (check (http-status r) 200)
    (check (http-body r) "hello, λ")
    (check (http-header r "x-custom") "yes")))

(define-test "the body is decoded by its charset"
  (check (http-body (http-get (url "latin1"))) "café"))

(define-test "a closed port is a condition naming the host (R-8)"
  (let* ((probe (start-server))
         (port (cdr probe)))
    [(car probe) stop]
    (check-error (http-get (string-append "http://127.0.0.1:" (number->string port) "/"))
                 "http: could not connect to 127.0.0.1")))

(define-test "a timeout is a condition"
  (check-error (http-get (url "slow") '() 1) "http: timed out after 1 s"))

(define-test "bad requests are errors before curl runs"
  (check-error (http-get "file:///etc/passwd") "http: not an http or https URL: file:///etc/passwd")
  (check-error (http-get "ftp://example.com/") "http: not an http or https URL")
  (check-error (http-get (url "hello") '(("X-Bad" . "a\r\nInjected: yes"))) "http: a header holds a line break: X-Bad")
  (check-error (http-get (url "hello") '() 0) "http: the timeout is not a positive number of seconds")
  (check-error (http-request 'POST (url "echo") '() 42) "http: the body is not a string")
  (check-error (http-get 42) "http: the URL is not a string")
  (check-error (http-status "not a response") "http-status: not an http response"))

(define-test "url-encode (RFC 3986), and a query built with it reaches the server"
  (check (url-encode "abcXYZ019-._~") "abcXYZ019-._~")
  (check (url-encode "a b&c=d/e?f") "a%20b%26c%3Dd%2Fe%3Ff")
  (check (url-encode "café λ") "caf%C3%A9%20%CE%BB")
  (check (url-encode "") "")
  (check (url-encode 'temperature_2m) "temperature_2m")
  (check-error (url-encode 42) "http: url-encode: the value is not a string")
  (check (http-body (http-get (string-append (url "query") "?q=" (url-encode "café & tea"))))
         "café & tea"))

(define-test "the accessors and the requests are documented, under Network"
  (for-each (lambda (n) (check-true (string? (documentation n))))
            '(http-request http-get http-response? http-status http-headers http-header http-body url-encode)))

(define-test "the program is the runtime's to find: COGLISP_CURL wins, else the platform's"
  (let* ((env [(smalltalk OSEnvironment) current])
         (old (get-environment-variable "COGLISP_CURL")))
    (check-true (string? [(smalltalk LispProcess) curlProgram]))
    [env at: "COGLISP_CURL" put: "no-such-curl-program"]
    (check [(smalltalk LispProcess) curlProgram] "no-such-curl-program")
    (check-error (http-get (url "hello")) "http: curl was not found (set COGLISP_CURL)")
    (if old [env at: "COGLISP_CURL" put: old] [env removeKey: "COGLISP_CURL"])
    (check (http-status (http-get (url "hello"))) 200)))

(define-test "a program is run from its argument list, with no shell (R-10)"
  (check [(smalltalk LispProcess) run: (list->array (list "no-such-program-xyz"))] (smalltalk-nil))
  (check [(smalltalk LispProcess) windowsCommandLine: (list->array (list "a" "b c" "" "say \"hi\"" "x\\" "x\\ y"))]
         "a \"b c\" \"\" \"say \\\"hi\\\"\" x\\ \"x\\ y\""))

;; Live HTTPS (AC-4), only with COGLISP_LIVE_HTTPS=1: a good certificate is
;; accepted, and each badssl.com host of the spike's answers is rejected.
(define-test "live: certificates are checked (AC-4; only with COGLISP_LIVE_HTTPS=1)"
  (when (equal? (get-environment-variable "COGLISP_LIVE_HTTPS") "1")
    (check (http-status (http-get "https://example.com/" '() 20)) 200)
    (for-each (lambda (host)
                (check-error (http-get (string-append "https://" host "/") '() 20)
                             (string-append "http: certificate rejected by " host)))
              '("expired.badssl.com" "self-signed.badssl.com" "untrusted-root.badssl.com"
                "wrong.host.badssl.com"))))

(run-tests)
