;;;; src/art-decor.lisp -- the ocean background, laid out for the screen size
;;;; and colored for the theme: sky, waterline and ripple, ambient current,
;;;; seabed decorations, sand, the status bar, and the help panel. All of them
;;;; are CREATURE instances like every other sprite (policy :NONE: none of
;;;; them ever leaves the world bounds). The art itself is data, in
;;;; art-decor-data.lisp.
;;;;
;;;; Colors are given as ROLES: a list of (MASK-CHARACTER FOREGROUND
;;;; [BACKGROUND [:REVERSE]]) entries of RGB-COLOR designators, resolved into
;;;; :ROLE-STYLES for the world's theme when a creature is built and again by
;;;; its restyler when the theme changes. BACKGROUND defaults to the theme's
;;;; :BG; :REVERSE marks a role that falls back to reverse video in the 16-color
;;;; and monochrome modes, which paint no background.
(in-package #:cl-asciiquarium)

(defun %role-style (theme foreground background reverse-p)
  (let ((mode (effective-color-mode)))
    (if (and reverse-p (member mode '(:ansi16 :mono)))
        (if (eq mode :mono)
            (make-style :reverse)
            (style-merge (color-style foreground :theme theme) (make-style :reverse)))
        (color-style foreground :theme theme :background background))))

(defun %resolve-roles (theme roles)
  (loop for (character foreground background flag) in roles
        collect (cons character
                      (%role-style theme foreground (or background :bg)
                                   (eq flag :reverse)))))

(defun %make-decor (world kind frames masks roles &key (x 0) (y 0) (z 0) frame-period)
  "Create a background CREATURE of KIND in WORLD from FRAMES, their MASKS, and
ROLES, remembering ROLES so RESTYLE-DECOR can recolor it for another theme."
  (let ((theme (world-theme world)))
    (make-creature :world world :kind kind :frames frames :masks masks
                   :role-styles (%resolve-roles theme roles)
                   :style (color-style :fg :theme theme)
                   :frame-period frame-period :z z :policy :none
                   :x x :y y :dx 0 :dy 0
                   :data (list :roles roles))))

(defun restyle-decor (world creature)
  "Recolor a %MAKE-DECOR creature for WORLD's current theme in place."
  (let ((theme (world-theme world)))
    (%set-creature-colors creature
                          :style (color-style :fg :theme theme)
                          :role-styles (%resolve-roles
                                        theme (getf (creature-data creature) :roles)))))

(defun %repeat-motif (motif width phase)
  (let ((length (length motif)))
    (with-output-to-string (out)
      (dotimes (column width)
        (write-char (char motif (mod (+ column phase) length)) out)))))

(defun %glyph-mask (text role)
  "Return a mask for TEXT that gives every non-space character ROLE, keeping
TEXT's spaces and line breaks."
  (map 'string
       (lambda (character)
         (if (member character '(#\Space #\Newline)) character role))
       text))

;;; -- Waterline and ripple ------------------------------------------------

(defparameter +waterline-highlight-period+ 6
  "Every sixth waterline column is the bright crest.")

(defun waterline-line (width phase)
  "Return (VALUES ART MASK): WIDTH columns of #\\~ with a bright #\\≈ crest on
every +WATERLINE-HIGHLIGHT-PERIOD+th column, shifted by PHASE."
  (let ((art (make-string width))
        (mask (make-string width)))
    (dotimes (column width)
      (let ((crest-p (zerop (mod (+ column phase) +waterline-highlight-period+))))
        (setf (char art column) (if crest-p #\≈ #\~)
              (char mask column) (if crest-p #\h #\w))))
    (values art mask)))

(defun make-waterline (world)
  "Create the slowly flowing waterline spanning the full width of WORLD."
  (let ((frames '()) (masks '()))
    (loop for phase from (1- +waterline-highlight-period+) downto 0
          do (multiple-value-bind (art mask) (waterline-line (world-width world) phase)
               (push art frames)
               (push mask masks)))
    (%make-decor world :waterline frames masks
                 '((#\w :waterline) (#\h :waterhi))
                 :y (world-waterline-row world) :frame-period 6)))

(defun make-ripple (world)
  "Create the faint ripple row just under the waterline."
  (let ((width (world-width world)))
    (%make-decor world :ripple
                 (loop for phase below 3
                       collect (%repeat-motif +ripple-motif+ width (* phase 2)))
                 (loop for phase below 3
                       collect (%glyph-mask (%repeat-motif +ripple-motif+ width (* phase 2)) #\r))
                 '((#\r :ambient))
                 :y (1+ (world-waterline-row world)) :frame-period 10)))

;;; -- Ambient current -----------------------------------------------------

(defparameter +ambient-current-rows+ 4)

(defun ambient-current-art (width phase &optional (spacing 1))
  "Return +AMBIENT-CURRENT-ROWS+ WIDTH-wide rows of drifting current marks,
SPACING rows apart (the rows between are transparent)."
  (with-output-to-string (out)
    (dotimes (row +ambient-current-rows+)
      (unless (zerop row)
        (dotimes (blank spacing) (terpri out)))
      (write-string (%repeat-motif +ambient-current-motif+ width (+ phase (* row 5))) out))))

(defun ambient-current-frames (width &optional (spacing 1))
  "Return the deterministic looping frames for WORLD's ambient current."
  (loop for phase below 4
        collect (ambient-current-art width phase spacing)))

(defun make-ambient-current (world)
  "Create the subtle animated current spread through the water."
  (let* ((top (+ (world-waterline-row world) 2))
         (band (- (world-sand-top world) top))
         (spacing (max 1 (floor band +ambient-current-rows+)))
         (frames (ambient-current-frames (world-width world) spacing)))
    (%make-decor world :ambient-current frames
                 (mapcar (lambda (frame) (%glyph-mask frame #\a)) frames)
                 '((#\a :ambient))
                 :y top :z -1 :frame-period 8)))

;;; -- Sand ----------------------------------------------------------------

(defun make-sand (world)
  "Create the sand band between the seabed and the status bar, or NIL when
the screen is too short to have one."
  (let* ((top (world-sand-top world))
         (rows (min (length +sand-motifs+) (- (world-status-row world) top))))
    (when (plusp rows)
      (let* ((lines (loop for motif in +sand-motifs+
                          for row below rows
                          collect (%repeat-motif motif (world-width world) (* row 3))))
             (art (format nil "~{~A~^~%~}" lines))
             (mask (format nil "~{~A~^~%~}"
                           (mapcar (lambda (line)
                                     (map 'string (lambda (character)
                                                    (if (char= character #\Space) #\s #\h))
                                          line))
                                   lines))))
        (%make-decor world :sand art mask
                     '((#\s :sand :sand) (#\h :sandhi :sand))
                     :y top :z 0)))))

;;; -- Seabed decorations --------------------------------------------------

(defun %seabed-y (world height)
  "The row a HEIGHT-tall decoration stands on the sand from, kept below the
waterline on screens too short for the full layout."
  (max (1+ (world-waterline-row world)) (- (world-sand-top world) height)))

(defun make-castle (world)
  "Create the castle, with lit windows, standing on the sand at the left."
  (multiple-value-bind (width height) (sprite-dimensions +castle-art+)
    (declare (ignore width))
    (%make-decor world :castle (list +castle-art+) (list +castle-mask+)
                 '((#\c :castle) (#\C :castlehi) (#\w :window))
                 :x 2 :y (%seabed-y world height) :z 1)))

(defun make-seaweed (world x)
  "Create one two-tone swaying seaweed strand rooted at column X."
  (multiple-value-bind (width height) (sprite-dimensions (first +seaweed-frames+))
    (declare (ignore width))
    (%make-decor world :seaweed +seaweed-frames+
                 (list +seaweed-mask+ +seaweed-mask+)
                 '((#\g :weed) (#\G :weed-alt))
                 :x x :y (%seabed-y world height) :z 1
                 :frame-period (random-between 8 16))))

(defparameter +seabed-ornaments+
  `((:coral ,+coral-art+ ,+coral-mask+ ((#\a :coral) (#\b :coral-alt)) 3/10)
    (:rock ,+rock-art+ ,+rock-mask+ ((#\r :rock) (#\R :rockhi)) 1/2)
    (:starfish ,+starfish-art+ ,+starfish-mask+ ((#\a :starfish) (#\A :starfish-alt)) 31/50)
    (:vent ,+vent-art+ ,+vent-mask+ ((#\r :rock) (#\R :rockhi) (#\m :bubble)) 18/25)
    (:chest ,+chest-art+ ,+chest-mask+ ((#\w :chest-wood) (#\g :gold) (#\k :chest-wood)) 9/10))
  "The static seabed ornaments, left to right: (KIND ART MASK ROLES
CENTER), CENTER being the fraction of the screen width the ornament is
centered on. The chest, rock, and vent are separate kinds because P4 finds
and animates them by kind.")

(defun seaweed-columns (world)
  "The columns MAKE-BACKGROUND-CREATURES roots its seaweed strands in."
  (let ((width (world-width world)))
    (loop for i below +default-seaweed-count+
          collect (round (* width (/ (1+ i) (1+ +default-seaweed-count+)))))))

(defparameter +ornament-search-columns+ 12
  "How far right of its preferred column an ornament may move to clear a
seaweed strand or the ornament before it.")

(defun make-seabed-ornaments (world)
  "Create every +SEABED-ORNAMENTS+ entry that fits WORLD: inside the width,
right of the castle and the previous ornament, on no seaweed column, and below
the waterline. Each ornament takes the first such column at or right of its
preferred one. Placement draws no random number, so it never shifts a seeded
run."
  (let ((width (world-width world))
        (blocked (seaweed-columns world))
        (left-limit (+ 2 (sprite-width +castle-art+) 1))
        (ornaments '()))
    (loop for (kind art mask roles center) in +seabed-ornaments+
          do (multiple-value-bind (art-width art-height) (sprite-dimensions art)
               (let ((y (- (world-sand-top world) art-height))
                     (x (loop for x from (max left-limit
                                              (- (round (* width center)) (floor art-width 2)))
                              repeat +ornament-search-columns+
                              when (and (<= (+ x art-width) (1- width))
                                        (notany (lambda (column) (<= x column (+ x art-width -1)))
                                                blocked))
                                return x)))
                 (when (and x (>= y (+ (world-waterline-row world) 2)))
                   (push (%make-decor world kind (list art) (list mask) roles
                                      :x x :y y :z 1)
                         ornaments)
                   (setf left-limit (+ x art-width 1))))))
    (nreverse ornaments)))

;;; -- Sky -----------------------------------------------------------------

(defparameter +sky-roles+
  '((#\u "#FFD166") (#\v "#F2B84B") (#\V "#FF8F70") (#\o "#E8D9A8")
    (#\c :muted) (#\s :fg) (#\S :muted)))

(defun %stamp-sprite (art-grid mask-grid art mask x y remap)
  "Copy ART and MASK into the character grids at (X, Y), renaming mask
characters through REMAP and dropping whatever falls outside the grids."
  (loop for art-line in (split-sprite-lines art)
        for mask-line in (split-sprite-lines mask)
        for row from y
        when (< -1 row (array-dimension art-grid 0))
          do (loop for column from x
                   for art-character across art-line
                   for mask-character across mask-line
                   when (and (< -1 column (array-dimension art-grid 1))
                             (char/= mask-character #\Space))
                     do (setf (aref art-grid row column) art-character
                              (aref mask-grid row column)
                              (or (cdr (assoc mask-character remap)) mask-character)))))

(defun %grid-text (grid)
  (with-output-to-string (out)
    (dotimes (row (array-dimension grid 0))
      (unless (zerop row) (terpri out))
      (dotimes (column (array-dimension grid 1))
        (write-char (aref grid row column) out)))))

(defun sky-sprite (world)
  "Return (VALUES ART MASK) for WORLD's sky: the sun by day (:CORAL), the sun
setting on the horizon at dusk (:ABYSS), the moon and stars at night
(:MOONLIGHT), with a cloud by day and at dusk. NIL when the waterline leaves
fewer than three sky rows."
  (let ((rows (world-waterline-row world))
        (width (world-width world)))
    (when (>= rows 3)
      (let ((art (make-array (list rows width) :initial-element #\Space))
            (mask (make-array (list rows width) :initial-element #\Space)))
        (ecase (world-theme world)
          (:coral
           (%stamp-sprite art mask +cloud-art+ +cloud-mask+ (floor width 5) 1 '((#\b . #\c)))
           (%stamp-sprite art mask +sun-art+ +sun-mask+ (- width 9) 0 '((#\b . #\u))))
          (:abyss
           (%stamp-sprite art mask +cloud-art+ +cloud-mask+ (floor width 5) 0 '((#\b . #\c)))
           (%stamp-sprite art mask +sunset-art+ +sunset-mask+ (- width 13) (- rows 2)
                          '((#\b . #\v) (#\f . #\V))))
          (:moonlight
           (dotimes (row (1- rows))
             (dotimes (column width)
               (let ((hash (mod (+ (* column 7) (* row 13)) 29)))
                 ;; Leave the moon (stamped at WIDTH - 9) a clear patch of sky.
                 (when (and (member hash '(0 11)) (< column (- width 11)))
                   (setf (aref art row column) (if (zerop hash) #\. #\*)
                         (aref mask row column) (if (zerop hash) #\S #\s))))))
           (%stamp-sprite art mask +moon-art+ +moon-mask+ (- width 9) 0 '((#\b . #\o)))))
        (values (%grid-text art) (%grid-text mask))))))

(defun make-sky (world)
  "Create the sky CREATURE for WORLD's theme, or NIL when there is no room."
  (multiple-value-bind (art mask) (sky-sprite world)
    (when art
      (%make-decor world :sky (list art) (list mask) +sky-roles+ :z -1))))

(defun restyle-sky (world creature)
  "Redraw the sky for WORLD's theme: its art changes with the time of day."
  (multiple-value-bind (art mask) (sky-sprite world)
    (when art
      (%set-creature-frames creature (list art) :masks (list mask)
                            :role-styles (%resolve-roles (world-theme world) +sky-roles+)))))

;;; -- Background composition ----------------------------------------------

(defun make-background-creatures (world)
  "Return every background CREATURE for WORLD's size and theme. The seaweed
strands draw their animation periods from *RANDOM-STATE* in the same order
as before the layout existed, so seeded runs keep their fish."
  (remove nil
            (append
             (list (make-ambient-current world)
                   (make-waterline world)
                   (make-castle world))
             (mapcar (lambda (column) (make-seaweed world column))
                     (seaweed-columns world))
             (list (make-sky world)
                   (when (< (1+ (world-waterline-row world)) (world-sand-top world))
                     (make-ripple world))
                   (make-sand world))
             (seabed-life world (make-seabed-ornaments world)))))

;;; -- Status bar ----------------------------------------------------------

(defparameter +status-bar-roles+
  '((#\A :hudbg :accent :reverse) (#\B :accent :accent :reverse)
    (#\n :fg :hudbg) (#\m :muted :hudbg) (#\l :live :hudbg)
    (#\k :accent :hudbg) (#\p :hudbg :hudbg))
  "A and B the theme badge (glyphs and padding), n text, m muted text, l the
live indicator, k a key name, p the bar's padding.")

(defparameter +time-of-day-labels+ '((:coral . "day") (:abyss . "dusk") (:moonlight . "night")))

(defparameter +status-bar-keys+
  '(("h" . "help") ("t" . "theme") ("space" . "pause") ("q" . "quit")))

(defun %status-groups (world)
  "Return the status bar's left summary as a list of (DROP-RANK . SEGMENTS)
groups in display order, each segment a (TEXT . ROLE). A group with a higher
DROP-RANK is dropped first when the screen is too narrow; rank 0 (the theme
badge and the swimming/paused state) is never dropped."
  (let ((paused-p (world-paused-p world)))
    (list (cons 0 (list (cons " " #\B) (cons "◆" #\A) (cons " " #\B)
                        (cons (visual-theme-label (world-theme world)) #\A)
                        (cons " " #\B)))
          (cons 3 (list (cons (cdr (assoc (world-theme world) +time-of-day-labels+)) #\n)
                        (cons " · " #\m) (cons "clear" #\n)))
          (cons 1 (list (cons (format nil "fish ~D" (world-fish-count world)) #\n)))
          (cons 2 (list (cons (format nil "dex ~D/~D"
                                      (length (world-discovered-species world))
                                      (length +fish-species+))
                              #\n)))
          (cons 0 (list (cons "●" (if paused-p #\m #\l))
                        (cons (if paused-p " paused" " swimming") #\n))))))

(defun %join-status-groups (groups)
  "Flatten GROUPS into one segment list: two spaces after the badge, a dot
between the groups that follow it."
  (loop for (nil . segments) in groups
        for index from 0
        append (append (cond ((= index 1) (list (cons "  " #\p)))
                             ((> index 1) (list (cons " · " #\m))))
                       segments)))

(defun %status-hints (world)
  (if (world-notification world)
      (list (cons (world-notification world) #\l) (cons " " #\p))
      (loop for (key . label) in +status-bar-keys+
            append (list (cons key #\k) (cons " " #\p) (cons label #\m) (cons "  " #\p)))))

(defun %segments-text (segments)
  (values (format nil "~{~A~}" (mapcar #'car segments))
          (format nil "~{~A~}"
                  (mapcar (lambda (segment)
                            (map 'string
                                 (lambda (character)
                                   (if (and (char= character #\Space)
                                            (not (member (cdr segment) '(#\A #\B))))
                                       #\p
                                       (cdr segment)))
                                 (car segment)))
                          segments))))

(defun %fitting-status-summary (groups width)
  "Return (VALUES ART MASK) for the widest summary that fits WIDTH, dropping
groups from the highest DROP-RANK down, then truncating what is left."
  (loop for rank from 3 downto 0
        do (multiple-value-bind (art mask) (%segments-text (%join-status-groups groups))
             (when (or (<= (length art) width) (zerop rank))
               (return (values (subseq art 0 (min width (length art)))
                               (subseq mask 0 (min width (length mask)))))))
           (setf groups (remove rank groups :key #'car))))

(defun hud-sprite (world)
  "Return (VALUES ART MASK ROLE-STYLES) for WORLD's one-row status bar,
spanning the full width: the summary on the left and the key hints (or the
current notification) on the right. The hints go first when the screen is
too narrow, then the summary's least important groups (see %STATUS-GROUPS)."
  (let ((width (world-width world)))
    (multiple-value-bind (right-art right-mask) (%segments-text (%status-hints world))
      (multiple-value-bind (left-art left-mask)
          (%fitting-status-summary (%status-groups world) width)
        (let* ((right-p (<= (+ (length left-art) 1 (length right-art)) width))
               (right-art (if right-p right-art ""))
               (right-mask (if right-p right-mask ""))
               (gap (- width (length left-art) (length right-art))))
          (values (concatenate 'string left-art
                               (make-string gap :initial-element #\Space) right-art)
                  (concatenate 'string left-mask
                               (make-string gap :initial-element #\p) right-mask)
                  (%resolve-roles (world-theme world) +status-bar-roles+)))))))

(defun make-hud (world)
  "Create the status bar on WORLD's bottom row."
  (multiple-value-bind (art mask role-styles) (hud-sprite world)
    (make-creature :world world :kind :hud :frames (list art) :masks (list mask)
                   :role-styles role-styles :z 100 :policy :none
                   :x 0 :y (world-status-row world) :dx 0 :dy 0)))

;;; -- Help panel ----------------------------------------------------------

(defparameter +help-entries+
  '(("q" . "quit") ("r" . "redraw") ("space" . "pause") ("+ / -" . "fish count")
    ("s" . "spawn shark") ("g" . "spawn guest") ("c" . "spawn school")
    ("a" . "ship and anchor") ("m" . "submarine") ("d" . "diver")
    ("t" . "cycle theme")
    ("u" . "status bar") ("h" . "this help"))
  "Every key binding the application implements (input.lisp), in help order.")

(defparameter +help-roles+
  '((#\o :muted :frame) (#\k :accent :frame) (#\n :fg :frame) (#\p :frame :frame))
  "o the box outline, k key names, n descriptions and the title, p padding.")

(defun help-sprite (world)
  "Return (VALUES ART MASK ROLE-STYLES): the rounded-corner help box listing
+HELP-ENTRIES+, key names in the accent color."
  (let* ((key-width (reduce #'max +help-entries+ :key (lambda (entry) (length (car entry)))))
         (label-width (reduce #'max +help-entries+ :key (lambda (entry) (length (cdr entry)))))
         (inner (+ 1 key-width 3 label-width 1))
         (title " controls ")
         (art-lines '())
         (mask-lines '()))
    (flet ((add (art mask) (push art art-lines) (push mask mask-lines)))
      (add (format nil "╭─~A~A╮" title
                   (make-string (- inner 1 (length title)) :initial-element #\─))
           (format nil "oo~A~Ao" (%glyph-mask-with-padding title #\n)
                   (make-string (- inner 1 (length title)) :initial-element #\o)))
      (loop for (key . label) in +help-entries+
            do (let ((key-text (format nil "~vA" key-width key))
                     (label-text (format nil "~vA" label-width label)))
                 (add (format nil "│ ~A   ~A │" key-text label-text)
                      (format nil "op~App~Apo"
                              (%glyph-mask-with-padding key-text #\k)
                              (concatenate 'string "p" (%glyph-mask-with-padding label-text #\n))))))
      (add (format nil "╰~A╯" (make-string inner :initial-element #\─))
           (format nil "o~Ao" (make-string inner :initial-element #\o))))
    (values (format nil "~{~A~^~%~}" (nreverse art-lines))
            (format nil "~{~A~^~%~}" (nreverse mask-lines))
            (%resolve-roles (world-theme world) +help-roles+))))

(defun %glyph-mask-with-padding (text role)
  "Return a mask for TEXT giving glyphs ROLE and spaces the padding role."
  (map 'string (lambda (character) (if (char= character #\Space) #\p role)) text))

(defun make-help-overlay (world)
  "Create the :HELP-OVERLAY CREATURE toggled by the `h' key (see
WORLD-TOGGLE-HELP-OVERLAY, input.lisp): an opaque panel just below the
waterline, painted at Z 99 so it sits above every creature but the status
bar. It is UI state, not aquarium population, so WORLD-REDRAW leaves it
alone."
  (multiple-value-bind (art mask role-styles) (help-sprite world)
    (make-creature :world world :kind :help-overlay :frames (list art) :masks (list mask)
                   :role-styles role-styles :z 99 :policy :none
                   :x 1 :y (1+ (world-waterline-row world)) :dx 0 :dy 0)))

(defun restyle-panel (sprite-function)
  "Return a restyler that rebuilds a panel from SPRITE-FUNCTION for the
world's current theme, keeping its position."
  (lambda (world creature)
    (multiple-value-bind (art mask role-styles) (funcall sprite-function world)
      (%set-creature-frames creature (list art) :masks (list mask) :role-styles role-styles))))

(dolist (kind '(:waterline :ripple :ambient-current :sand :castle :seaweed
                :coral :rock :starfish :vent :chest))
  (register-creature-restyler kind #'restyle-decor))
(register-creature-restyler :sky #'restyle-sky)
(register-creature-restyler :hud (restyle-panel #'hud-sprite))
(register-creature-restyler :help-overlay (restyle-panel #'help-sprite))
