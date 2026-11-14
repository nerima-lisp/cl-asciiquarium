;;;; src/palette.lisp -- 24-bit theme palettes and color-mode style resolution.
;;;;
;;;; Every color decision resolves here, once, when a creature or sprite
;;;; prototype is built. Nothing on the per-frame render path converts a color:
;;;; the resulting style lists are baked into prepared blit runs
;;;; (creature-cache.lisp), whose cells cl-tty-kit shares into the frame and
;;;; whose SGR prefix it caches per cell.
(in-package #:cl-asciiquarium)

(defparameter +color-modes+ '(:truecolor :ansi256 :ansi16 :mono)
  "How an RGB color reaches the terminal: a 24-bit SGR color, the nearest
xterm 256-color index, the nearest of the 16 system colors, or no color.")

(defvar *color-mode* :ansi16
  "The active member of +COLOR-MODES+. Bound by RUN from --color; the :ANSI16
default keeps library callers that never bind it on the 16-color look. A true
*MONOCHROME* overrides it to :MONO.")

(defun effective-color-mode ()
  (if *monochrome* :mono *color-mode*))

(defun %hex-rgb (hex)
  (multiple-value-list (parse-hex-color hex)))

(defun %parse-color-table (entries)
  (loop for (name hex) on entries by #'cddr
        nconc (list name (%hex-rgb hex))))

(defparameter +theme-rgb-palettes+
  (loop for (theme . entries)
          in '((:coral
                :bg "#0E2629" :frame "#12302F" :fg "#EAF4F0" :muted "#8FB3AD"
                :accent "#FF8F70" :live "#FFD166" :hudbg "#143538"
                :waterline "#4FB8AA" :waterhi "#CFF5EC" :ambient "#1E4A4A"
                :sand "#B89A6E" :sandhi "#E3C597" :castle "#C98C6E"
                :castlehi "#EDB898" :window "#FFD166" :bubble "#9FE3D6"
                :rock "#5E8A86" :rockhi "#8FB3AD" :weed "#D9605C"
                :weed-alt "#F29A6B")
               (:abyss
                :bg "#081521" :frame "#0C1A27" :fg "#D3E3EE" :muted "#7F98AB"
                :accent "#5FD7E6" :live "#7EE0A1" :hudbg "#0F2333"
                :waterline "#3E8DB3" :waterhi "#A7DCF0" :ambient "#1A3850"
                :sand "#6E6049" :sandhi "#9C8762" :castle "#5D7489"
                :castlehi "#93A9BD" :window "#F2B84B" :bubble "#7CC4E2"
                :rock "#4C6070" :rockhi "#6C8296" :weed "#1F8A6A"
                :weed-alt "#3CC197")
               (:moonlight
                :bg "#0A0D18" :frame "#0F1322" :fg "#DCE2EF" :muted "#8089A6"
                :accent "#E8D9A8" :live "#8EC5F0" :hudbg "#121830"
                :waterline "#6F82AC" :waterhi "#E6ECF7" :ambient "#192139"
                :sand "#363C55" :sandhi "#565E7E" :castle "#59627E"
                :castlehi "#8A93B0" :window "#E8D9A8" :bubble "#A9B8D6"
                :rock "#363C55" :rockhi "#565E7E" :weed "#34506F"
                :weed-alt "#5D7FA3"))
        collect (cons theme (%parse-color-table entries)))
  "Per-theme role colors as (R G B) lists, keyed by role keyword. The named
16-color +VISUAL-THEME-PALETTES+ (world.lisp) stays as the 16-color look.")

(defparameter +fixed-rgb-colors+
  (%parse-color-table
   '(:chest-wood "#A3743A" :gold "#F2D14B" :coral "#FF7FA8"
     :coral-alt "#FF8F70" :starfish "#FF8F70" :starfish-alt "#FFD166"
     :crab "#FF6B5B" :gull "#D3E3EE" :gull-beak "#F2C14B" :submarine "#F2D14B"
     :octopus "#C9708A" :ink "#2A2235" :sonar "#8EC5F0" :food "#E8C27A"
     :rare-glow "#FFE08A" :stripe "#FFFFFF"))
  "Theme-independent colors as (R G B) lists, keyed by role keyword.")

(defun rgb-color (designator &optional theme)
  "Return DESIGNATOR as an (R G B) list. DESIGNATOR is a \"#rrggbb\" string, an
(R G B) list, or a role keyword: THEME's palette entry when THEME has one,
otherwise a +FIXED-RGB-COLORS+ entry."
  (or (typecase designator
        (string (%hex-rgb designator))
        (cons designator)
        (keyword
         (or (and theme
                  (getf (cdr (assoc theme +theme-rgb-palettes+)) designator))
             (getf +fixed-rgb-colors+ designator))))
      (error 'asciiquarium-invalid-argument
             :value designator
             :expected (format nil "a \"#rrggbb\" string, an (R G B) list, or a color role of theme ~(~S~) or the fixed colors"
                               theme))))

(defun %mode-color-entry (constructor rgb mode)
  (destructuring-bind (red green blue) rgb
    (ecase mode
      (:truecolor (funcall constructor red green blue))
      (:ansi256 (funcall constructor (rgb-to-256 red green blue)))
      (:ansi16 (funcall constructor (rgb-to-ansi16 red green blue))))))

(defun color-style (foreground &key theme (background :bg) bold-p)
  "Return the cl-tty-kit style painting FOREGROUND (a RGB-COLOR designator)
over BACKGROUND in the effective color mode, or NIL in :MONO. BACKGROUND
defaults to THEME's :BG role; NIL leaves the terminal background. The 16-color
mode never paints a background, so the terminal's own background shows
through exactly as it does today."
  (let ((mode (effective-color-mode)))
    (unless (eq mode :mono)
      (let ((items (list (%mode-color-entry #'style-fg
                                            (rgb-color foreground theme)
                                            mode))))
        (when (and background (not (eq mode :ansi16)))
          (push (%mode-color-entry #'style-bg (rgb-color background theme) mode)
                items))
        (when bold-p
          (push :bold items))
        (apply #'make-style items)))))

(defparameter +mask-roles+
  '((#\b . :body) (#\f . :fin) (#\t . :tail) (#\e . :eye)
    (#\s . :stripe) (#\l . :light))
  "Mask characters a fish sprite uses, and the role each one paints.")

(defun mask-role-styles (color-set &key theme (background :bg) extra-roles)
  "Return the :ROLE-STYLES alist MAKE-CREATURE expects for a masked sprite.
COLOR-SET is the species' (BODY FIN TAIL EYE) list of RGB-COLOR designators;
the stripe role #\\s is :STRIPE (white) and the light role #\\l is :RARE-GLOW
from +FIXED-RGB-COLORS+. EXTRA-ROLES is an alist of (CHARACTER . DESIGNATOR)
that adds or overrides roles, for sprites with their own mask letters.
Every style carries BACKGROUND as COLOR-STYLE does."
  (destructuring-bind (body fin tail eye) color-set
    (let ((designators (list (cons #\b body) (cons #\f fin) (cons #\t tail)
                             (cons #\e eye) (cons #\s :stripe)
                             (cons #\l :rare-glow))))
      (loop for (character . designator) in extra-roles
            do (setf designators
                     (acons character designator
                            (remove character designators :key #'car))))
      (loop for (character . designator) in designators
            collect (cons character
                          (color-style designator
                                       :theme theme
                                       :background background))))))

(defun detect-color-mode (&key colorterm term no-color)
  "Return the member of +COLOR-MODES+ a terminal described by the COLORTERM,
TERM, and NO_COLOR environment values (strings or NIL) supports: :MONO when
NO_COLOR is set and non-empty, :TRUECOLOR when COLORTERM is truecolor or 24bit,
:ANSI256 when TERM names a 256color terminal, and :ANSI16 otherwise. Pure, so
the caller (cli.lisp) owns reading the environment."
  (cond
    ((and no-color (plusp (length no-color))) :mono)
    ((and colorterm (member colorterm '("truecolor" "24bit") :test #'string-equal))
     :truecolor)
    ((and term (search "256color" term :test #'char-equal)) :ansi256)
    (t :ansi16)))

(defun resolve-color-mode (choice &key colorterm term no-color monochrome-p)
  "Return the color mode for the --color CHOICE string (auto, truecolor, 256,
16, or mono; NIL means auto). MONOCHROME-P (the --monochrome alias) forces
:MONO; an explicit CHOICE other than auto wins over NO_COLOR."
  (cond
    (monochrome-p :mono)
    ((or (null choice) (string-equal choice "auto"))
     (detect-color-mode :colorterm colorterm :term term :no-color no-color))
    ((string-equal choice "truecolor") :truecolor)
    ((string-equal choice "256") :ansi256)
    ((string-equal choice "16") :ansi16)
    ((string-equal choice "mono") :mono)
    (t (error 'asciiquarium-invalid-argument
              :value choice
              :expected "a --color value, one of auto, truecolor, 256, 16, mono"))))

(defparameter +ascii-substitutions+
  '((#\≈ . #\~) (#\◆ . #\*) (#\· . #\.) (#\● . #\*) (#\• . #\o)
    (#\° . #\o) (#\♥ . #\*) (#\▒ . #\#) (#\¦ . #\|) (#\│ . #\|)
    (#\─ . #\-) (#\╭ . #\+) (#\╮ . #\+) (#\╰ . #\+) (#\╯ . #\+)
    (#\✦ . #\*) (#\∘ . #\o))
  "One-column ASCII stand-ins for every non-ASCII symbol a sprite draws. Each
replacement keeps the column count, so a mask stays aligned with its art.")

(defun ascii-text (text)
  "Return TEXT with every +ASCII-SUBSTITUTIONS+ symbol replaced, or TEXT
itself when it has none."
  (if (every (lambda (character) (< (char-code character) 128)) text)
      text
      (map 'string
           (lambda (character)
             (or (cdr (assoc character +ascii-substitutions+)) character))
           text)))

(defun background-style (theme &optional (role :bg))
  "Return the style painting THEME's ROLE color as a background with no
foreground, or NIL in :ANSI16 and :MONO, which never paint a background."
  (let ((mode (effective-color-mode)))
    (when (member mode '(:truecolor :ansi256))
      (make-style (%mode-color-entry #'style-bg (rgb-color role theme) mode)))))

(defun background-cell (theme)
  "Return the blank cell every uncovered screen position shows under THEME:
a space over THEME's :BG color, or NIL (the plain blank cell) when the color
mode paints no background. Renderers clear to this cell, so water shows
between sprites without a full-screen background creature."
  (let ((style (background-style theme)))
    (and style (make-cell :char #\Space :style style))))
