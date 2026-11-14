;;;; src/art-fish-data.lisp -- original species art, masks, and traits.
;;;; All art below is original to this repository; none is copied from the
;;;; classic Perl `asciiquarium`.
;;;; Turtle and squid source art faces left and is normalized when loaded.
;;;; All stored art faces right; masks reverse without swapping glyphs.
(in-package #:cl-asciiquarium)

(defstruct (fish-species-entry
            (:constructor make-fish-species-entry
                (name art &key mask color-sets speed-range small-p drifts-p spawn-probability)))
  "One entry of +FISH-SPECIES+. A struct rather than a plist so a typo'd slot
is a compile-time error instead of a silently NIL GETF."
  (name nil :type keyword)
  (art "" :type string)
  (mask "" :type string)
  ;; Each palette is ordered body, fin, tail, eye, in #RRGGBB notation.
  (color-sets nil :type list)
  (speed-range nil :type list)
  (small-p nil :type boolean)
  (drifts-p nil :type boolean)
  (spawn-probability nil :type (or null rational)))

(defparameter +turtle-source-art+
  (format nil "   .---.~% _/_\\_/_\\_~%(o        )=~%  \"-'  \"-'"))

(defparameter +turtle-source-mask+
  (format nil "~{~A~^~%~}" '("   fffff" " fffffffff" "be        bt" "  bbb  bbb")))

(defparameter +squid-source-art+ (format nil "  ,--.~%<(o   )~~~~=~%  `--'"))

(defparameter +squid-source-mask+
  (format nil "~{~A~^~%~}" '("  ffff" "bbe   bttt" "  ffff")))

(defparameter +fish-species+
  (list
   (make-fish-species-entry :dart
    (format nil "  __~%>=(('>~%  ``")
    :mask (format nil "  ff~%ttbbeb~%  ff")
    :color-sets '(("#5FD7E6" "#2F9FB3" "#1F6F80" "#F4FBFF")
                  ("#7EE0A1" "#4BB377" "#2F7D52" "#F0FFF5"))
    :speed-range '(0.5 0.7)
    :small-p t)
   (make-fish-species-entry :puffer
    (format nil " .--.~%((o o))=>~%  `--'")
    :mask (format nil " ffff~%bbebebbtt~%  ffff")
    :color-sets '(("#F2B84B" "#C98A2A" "#8A5E1E" "#FFF6E0"))
    :speed-range '(0.15 0.25))
   (make-fish-species-entry :ribbon
    (format nil "  ..-.~%=<(o)===>~%  `-'")
    :mask (format nil "  ffff~%ttbebbbbb~%  fff")
    :color-sets '(("#B79CFF" "#8A6FDB" "#5E4AA0" "#F5F0FF")
                  ("#FF7A6B" "#D4524A" "#94372F" "#FFF1EE"))
    :speed-range '(0.3 0.4))
   (make-fish-species-entry :angel
    (format nil "  /\\~%<((*>~%  \\/")
    :mask (format nil "  ff~%tbbeb~%  ff")
    :color-sets '(("#FF7A6B" "#D4524A" "#94372F" "#FFF1EE")
                  ("#F2B84B" "#C98A2A" "#8A5E1E" "#FFF6E0"))
    :speed-range '(0.25 0.35))
   (make-fish-species-entry :guppy
    (format nil " _~%>=(o)>~% `")
    :mask (format nil " f~%ttbebb~% f")
    :color-sets '(("#7EE0A1" "#4BB377" "#2F7D52" "#F0FFF5")
                  ("#5FD7E6" "#2F9FB3" "#1F6F80" "#F4FBFF"))
    :speed-range '(0.4 0.6)
    :small-p t)
   (make-fish-species-entry :clown
    (format nil "  _~%>|)|)o>~%  `")
    :mask (format nil "  f~%tsbsbeb~%  f")
    :color-sets '(("#FF8A3D" "#D9662A" "#A3481C" "#FFFFFF"))
    :speed-range '(0.3 0.45)
    :small-p t)
   (make-fish-species-entry :tang
    (format nil " ,-/|~%>((  o>~% `-\\|")
    :mask (format nil " ffff~%tbb  eb~% ffff")
    :color-sets '(("#4F8DFF" "#F2D14B" "#F2D14B" "#FFFFFF"))
    :speed-range '(0.35 0.5))
   (make-fish-species-entry :eel
    (format nil "~~=~~=~~=~~=(o>")
    :mask (format nil "fbfbfbfbbeb")
    :color-sets '(("#9BCB6A" "#6E9A45" "#4E7030" "#FFE08A")
                  ("#C9A86A" "#9C8250" "#705C38" "#FFFFFF"))
    :speed-range '(0.2 0.3))
   (make-fish-species-entry :lantern
    (format nil "      o~%  .--.|~%=(( o  >~%  `--'")
    :mask (format nil "      l~%  bbbbf~%tbbbebbb~%  bbbb")
    :color-sets '(("#8C7AA6" "#6E5E87" "#52456A" "#FFFFFF"))
    :speed-range '(0.12 0.18))
   (make-fish-species-entry :jelly
    (format nil " .-^-.~%(     )~% )|(|~% (|)(")
    :mask (format nil " bbbbb~%b     b~% ffff~% tttt")
    :color-sets '(("#F2A6D8" "#C97FB3" "#9E6A9E" "#FFFFFF")
                  ("#A6E3F2" "#7FBFD9" "#5E97B3" "#FFFFFF"))
    :speed-range '(0.04 0.07)
    :drifts-p t)
   (make-fish-species-entry :seahorse
    (format nil " _~%(o>~% )|~%(/~% \\_)")
    :mask (format nil " f~%beb~% bf~%bb~% ttt")
    :color-sets '(("#FFB347" "#D98C2A" "#A36A1C" "#FFFFFF"))
    :speed-range '(0.03 0.05)
    :drifts-p t)
   (make-fish-species-entry :turtle
    (mirror-sprite-text
     +turtle-source-art+)
    ;; The shell row has ten cells: one transparent cell and nine fin cells.
    :mask (mirror-sprite-mask +turtle-source-mask+)
    :color-sets '(("#A3C98A" "#6E8A4E" "#7FA36A" "#FFFFFF"))
    :speed-range '(0.12 0.16))
   (make-fish-species-entry :squid
    (mirror-sprite-text +squid-source-art+)
    :mask (mirror-sprite-mask +squid-source-mask+)
    :color-sets '(("#F2B8A0" "#D98C76" "#B36B58" "#FFFFFF"))
    :speed-range '(0.45 0.6))
   (make-fish-species-entry :butterfly
    (format nil "  /\\~% /  \\~%<( o  >~% \\  /~%  \\/")
    :mask (format nil "  ff~% f  f~%tb e  b~% f  f~%  ff")
    :color-sets '(("#F2E14B" "#F4F1EA" "#C9B83A" "#FFFFFF"))
    :speed-range '(0.25 0.35))
   (make-fish-species-entry :golden
    (format nil "  __~%>=(('>~%  ``")
    :mask (format nil "  ff~%ttbbeb~%  ff")
    :color-sets '(("#FFD700" "#E6B800" "#B38F00" "#FFFFFF"))
    :speed-range '(0.5 0.7)
    :spawn-probability 3/100)
   (make-fish-species-entry :oarfish
    (format nil
            "  ,,,,,,,,,,,,,~%=~~~~~~~~~~~~~~~~~~~~~~~~~~(o>~%             `")
    :mask (format nil "  fffffffffffff~%tbbbbbbbbbbbbbbeb~%             f")
    :color-sets '(("#D9E2EC" "#FF5A5F" "#B3BCCF" "#FFFFFF"))
    :speed-range '(0.15 0.2)
    :spawn-probability 2/100)))

(defparameter +fish-death-art+
  (format nil " .-.~%(x x)~% `-'")
  "The brief death-animation frame a fish switches to when the shark or a
dropped anchor catches it. A single frame is enough: DEATH-ANIMATION-TICKS
below controls how long it stays on screen before being removed.")

(defparameter +death-animation-ticks+ 6
  "How many ticks a caught fish's death frame stays visible before removal.")
