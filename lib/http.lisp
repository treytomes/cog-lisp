;;; http.lisp -- http-request and http-get (specs/https-and-json.md R-6 to R-12)
;;;
;;; A request is made by the system's curl, the same way on every platform: the
;;; runtime finds it (COGLISP_CURL, else Windows' own curl.exe, else curl on the
;;; PATH) and runs it with an argument list, never through a shell
;;; (LispProcess in src/coglisp-runtime.st). A program sees none of that: only
;;; requests, responses and conditions. Certificates are checked by curl against
;;; the system's trust store, and there is no way to turn that off.
;;;
;;; Loaded by the build and compiled by the seed, so it is plain code.

;; A failure is an error whose message starts with "http:".
(define (%http-fail . parts)
  (error (apply string-append (cons "http: " parts))))

(define (%http-lower s) (list->string (map char-downcase (string->list s))))

(define (%http-trim s)
  (let loop ((i 0) (j (string-length s)))
    (cond ((and (< i j) (char-whitespace? (string-ref s i))) (loop (+ i 1) j))
          ((and (< i j) (char-whitespace? (string-ref s (- j 1)))) (loop i (- j 1)))
          (else (substring s i j)))))

;; the index of the first ch in s at or after start, or #f
(define (%http-index s ch start)
  (let loop ((i start))
    (cond ((>= i (string-length s)) #f)
          ((eq? (string-ref s i) ch) i)
          (else (loop (+ i 1))))))

(define (%http-scheme-ok? url)
  (let ((u (%http-lower url)))
    (or (and (>= (string-length u) 7) (string=? (substring u 0 7) "http://"))
        (and (>= (string-length u) 8) (string=? (substring u 0 8) "https://")))))

;; the host of url: after "://" and any "user@", up to a port, path, query or fragment
(define (%http-host url)
  (let* ((start (let ((i (%http-index url #\: 0))) (if i (+ i 3) 0)))
         (end (let loop ((i start))
                (if (or (>= i (string-length url)) (memv (string-ref url i) '(#\/ #\? #\#)))
                    i
                    (loop (+ i 1)))))
         (authority (substring url start end))
         (at (let loop ((i (- (string-length authority) 1)))
               (cond ((< i 0) #f) ((eq? (string-ref authority i) #\@) i) (else (loop (- i 1))))))
         (hostport (if at (substring authority (+ at 1) (string-length authority)) authority)))
    (if (and (> (string-length hostport) 0) (eq? (string-ref hostport 0) #\[))
        (let ((close (%http-index hostport #\] 0)))
          (if close (substring hostport 0 (+ close 1)) hostport))
        (let ((colon (%http-index hostport #\: 0)))
          (if colon (substring hostport 0 colon) hostport)))))

(define (%http-line-break? s)
  (or (%http-index s #\return 0) (%http-index s #\newline 0)))

(define (%http-text x who)
  (cond ((string? x) x)
        ((symbol? x) (symbol->string x))
        (else (%http-fail who " is not a string"))))

;; curl's arguments, before the files the runtime adds
(define (%http-arguments method url headers body timeout)
  (append
   (list "-q" "-sS" "--proto" "=http,https" "--proto-redir" "=http,https"
         "-L" "--max-redirs" "10" "--max-time" (number->string timeout))
   (if (string=? method "HEAD") (list "--head") (list "-X" method))
   ;; a body is a string sent as UTF-8: say so, unless the program names a type
   (if (and body (not (any (lambda (h) (and (or (string? (car h)) (symbol? (car h)))
                                            (string=? (%http-lower (%http-text (car h) "a header name")) "content-type")))
                           headers)))
       (list "-H" "Content-Type: text/plain; charset=utf-8")
       '())
   (append-map (lambda (h)
                 (let ((name (%http-text (car h) "a header name"))
                       (value (%http-text (cdr h) "a header value")))
                   (if (or (%http-line-break? name) (%http-line-break? value))
                       (%http-fail "a header holds a line break: " name))
                   (list "-H" (string-append name ": " value))))
               headers)
   (list "--url" url)))

;; the header lines of the last response in curl's -D file (after redirects and 100s)
(define (%http-last-block text)
  (let loop ((lines (string-split text #\newline)) (current '()) (last '()))
    (if (null? lines)
        (reverse (if (pair? current) current last))
        (let ((line (%http-trim (car lines))))
          (cond ((string=? line "")
                 (loop (cdr lines) '() (if (pair? current) current last)))
                (else (loop (cdr lines) (cons line current) last)))))))

(define (%http-status-of line)
  (let* ((sp (%http-index line #\space 0))
         (rest (if sp (substring line (+ sp 1) (string-length line)) ""))
         (sp2 (%http-index rest #\space 0))
         (n (string->number (if sp2 (substring rest 0 sp2) rest))))
    (if n n (%http-fail "an unreadable status line: " line))))

(define (%http-header-pairs lines)
  (filter-map (lambda (line)
                (let ((colon (%http-index line #\: 0)))
                  (and colon
                       (cons (%http-lower (%http-trim (substring line 0 colon)))
                             (%http-trim (substring line (+ colon 1) (string-length line)))))))
              lines))

;; the charset parameter of a Content-Type value, or #f
(define (%http-charset content-type)
  (and content-type
       (let loop ((params (cdr (string-split content-type #\;))))
         (and (pair? params)
              (let* ((p (%http-trim (car params)))
                     (eq (%http-index p #\= 0)))
                (if (and eq (string=? (%http-lower (%http-trim (substring p 0 eq))) "charset"))
                    (let ((v (%http-trim (substring p (+ eq 1) (string-length p)))))
                      (if (and (> (string-length v) 1) (eq? (string-ref v 0) #\"))
                          (substring v 1 (- (string-length v) 1))
                          v))
                    (loop (cdr params))))))))

(define (%http-curl-message text)
  (let* ((line (let ((nl (%http-index text #\newline 0))) (%http-trim (if nl (substring text 0 nl) text))))
         (close (and (string-prefix? "curl: (" line) (%http-index line #\) 0))))
    (if close (%http-trim (substring line (+ close 1) (string-length line))) line)))

;; curl's exit codes for TLS and certificate failures
(define %http-tls-codes '(35 51 53 54 58 59 60 64 66 77 80 82 83 90 91 98))

(define (%http-raise code url timeout message)
  (let ((host (%http-host url)))
    (cond ((memv code '(6 7)) (%http-fail "could not connect to " host))
          ((= code 28) (%http-fail "timed out after " (number->string timeout) " s: " url))
          ((memv code %http-tls-codes) (%http-fail "certificate rejected by " host ": " message))
          ((= code 47) (%http-fail "too many redirects: " url))
          (else (%http-fail "request failed (curl " (number->string code) "): " message)))))

(define (http-request method url . options)
  "(http-request method url [headers] [body] [timeout])
Makes an HTTP or HTTPS request and answers its response, read with http-status, http-headers, http-header and http-body. method is a symbol or string (GET, POST, ...); headers an alist of (name . value) strings; body a string, sent as UTF-8 (as text/plain; charset=utf-8 unless headers give a Content-Type), or #f; timeout in seconds, 30 by default. Redirects are followed, up to 10. A 4xx or 5xx status is a response; a failure to connect, a timeout or a rejected certificate is an error whose message starts with http:."
  (let* ((headers (if (pair? options) (car options) '()))
         (body (if (and (pair? options) (pair? (cdr options))) (cadr options) #f))
         (timeout (if (and (pair? options) (pair? (cdr options)) (pair? (cddr options))) (caddr options) 30))
         (method (string-upcase (%http-text method "the method"))))
    (if (not (string? url)) (%http-fail "the URL is not a string"))
    (if (not (%http-scheme-ok? url)) (%http-fail "not an http or https URL: " url))
    (if (not (and (number? timeout) (> timeout 0))) (%http-fail "the timeout is not a positive number of seconds"))
    (if (and body (not (string? body))) (%http-fail "the body is not a string"))
    (let* ((result [(smalltalk LispProcess) curl: (list->vector (%http-arguments method url headers body timeout))
                                            body: (if body body (smalltalk-nil))])
           (code (vector-ref result 0)))
      (cond ((smalltalk-nil? code) (%http-fail "curl was not found (set COGLISP_CURL)"))
            ((not (= code 0)) (%http-raise code url timeout (%http-curl-message (vector-ref result 3))))
            (else
             (let* ((lines (%http-last-block [(smalltalk LispProcess) decode: (vector-ref result 1) charset: "iso-8859-1"]))
                    (pairs (if (pair? lines) (%http-header-pairs (cdr lines)) '()))
                    (status (if (pair? lines) (%http-status-of (car lines)) (%http-fail "no response from " (%http-host url))))
                    (type (let ((p (assoc "content-type" pairs))) (and p (cdr p))))
                    (charset (%http-charset type)))
               [(smalltalk LispHttpResponse) status: status headers: pairs
                 body: [(smalltalk LispProcess) decode: (vector-ref result 2) charset: (if charset charset (smalltalk-nil))]]))))))

(define (http-get url . options)
  "(http-get url [headers] [timeout])
A GET request: (http-request 'GET url headers #f timeout)."
  (let ((headers (if (pair? options) (car options) '()))
        (timeout (if (and (pair? options) (pair? (cdr options))) (cadr options) 30)))
    (http-request "GET" url headers #f timeout)))

(define (http-response? x)
  "(http-response? x)
#t if x is a response from http-request."
  (if [x isKindOf: (smalltalk LispHttpResponse)] #t #f))

(define (%http-check r who)
  (if (not (http-response? r)) (error (string-append who ": not an http response") r)))

(define (http-status r)
  "(http-status response)
The response's status code, an integer such as 200 or 404."
  (%http-check r "http-status")
  [r status])

(define (http-headers r)
  "(http-headers response)
The response's headers, an alist of (name . value) strings with the names in lower case, in the order the server sent them. After a redirect they are the last response's."
  (%http-check r "http-headers")
  [r headers])

(define (http-header r name)
  "(http-header response name)
The value of the response's first header called name (in any case), or #f."
  (%http-check r "http-header")
  (let ((p (assoc (%http-lower (%http-text name "the header name")) [r headers])))
    (and p (cdr p))))

(define (http-body r)
  "(http-body response)
The response's body, a string decoded by the charset of its Content-Type (UTF-8 when it names none)."
  (%http-check r "http-body")
  [r body])

(define %url-hex "0123456789ABCDEF")

(define (url-encode s)
  "(url-encode string)
string percent-encoded for a URL's query or path (RFC 3986): letters, digits and - . _ ~ stay as they are, and every other byte of its UTF-8 is %XX. (string-append url \"?q=\" (url-encode \"café au lait\")) asks for café au lait."
  (let* ((text (%http-text s "url-encode: the value"))
         (bytes [[(smalltalk ZnUTF8Encoder) new] encodeString: text])
         (n [bytes size])
         (out (open-output-string)))
    (let loop ((i 1))
      (if (<= i n)
          (let ((b [bytes at: i]))
            (if (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (and (>= b 48) (<= b 57))
                    (memv b '(45 46 95 126)))
                (write-char (integer->char b) out)
                (begin (write-char #\% out)
                       (write-char (string-ref %url-hex (quotient b 16)) out)
                       (write-char (string-ref %url-hex (remainder b 16)) out)))
            (loop (+ i 1)))))
    (get-output-string out)))

(for-each (lambda (p) [p category: "Network"])
          (list http-request http-get http-response? http-status http-headers http-header http-body url-encode))
