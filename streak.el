;;; streak.el --- Track a daily streak in your Mode Line -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Colin Woodbury
;;
;; Author: Colin Woodbury <https://www.fosskers.ca>
;; Maintainer: Colin Woodbury <colin@fosskers.ca>
;; Created: June 18, 2021
;; Modified: September 9, 2021
;; Version: 2.1.0
;; Keywords: calendar
;; Homepage: https://github.com/fosskers/streak
;; Package-Requires: ((emacs "27.1"))
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;; `streak-mode' is a minor mode for tracking daily streaks. Exercising?
;; Learning a language? Trying to quit a bad habit? Track your success in your
;; mode line!
;;
;; Start a new streak with `streak-new'. If you've broken a streak, it can be
;; reset with `streak-reset'. Don't worry, you'll do better next time!
;;
;; See the Github README for configuration specifics.
;;
;;; Code:

(require 'xdg)

(defvar streak--streak-message nil
  "String representation of the current streak.")

;;;###autoload
(define-minor-mode streak-mode
  "Display the number of days of a successful streak in the mode line."
  :init-value nil
  :global t
  :group 'streak
  :lighter " Streak"
  (if streak-mode
      (progn
        (unless streak--streak-message
          (streak-update))
        (add-to-list 'global-mode-string '(t streak--streak-message)))
    (setq global-mode-string (delete '(t streak--streak-message) global-mode-string))))

;; TODO Use `file-name-concat' once Emacs 28 is the lowest supported version.
(defcustom streak-file (expand-file-name "streak" (xdg-cache-home))
  "The location to save the start of the current streak."
  :group 'streak
  :type 'file)

(defcustom streak-formatters nil
  "An alist of keys paired with functions to custom format streak values.

Each function is passed the length of the streak in days, and
must yield a string."
  :group 'streak
  :type '(alist :key-type string :value-type function))

(defun streak--seconds-since-unix-epoch ()
  "The number of seconds since the Unix Epoch."
  (time-convert nil 'integer))

(defun streak--current ()
  "Read the streak file and render the current streaks."
  (streak--render-streaks (streak--current-streaks)))

(defun streak--current-streaks ()
  "Read the streak file and return a hashtable of the current streaks.
In the event that no streak file existed, an empty hashtable is
returned. This is useful for setting the initial streak the first
time `streak-mode' is used."
  (let* ((buffer (find-file-noselect streak-file))
         (json (streak--json-parse-buffer-lenient buffer)))
    (cond ((hash-table-p json) json)
          ;; TODO This legacy compat logic can be removed after a while, once
          ;; there's probably nobody left on the old format.
          ((integerp json) (let ((streaks (make-hash-table :test 'equal)))
                             (puthash "legacy" json streaks)
                             streaks))
          (t (error "Unexpected json parsed from streak file")))))

(defun streak--json-parse-buffer-lenient (buffer)
  "Parse the given BUFFER and return legal json no matter what."
  (condition-case nil
      (with-current-buffer buffer
        ;; `json-parse-buffer' starts parsing from `point', and we want to
        ;; guarantee it's at the beginning of the buffer.
        (goto-char (point-min))
        (json-parse-buffer))
    (error (make-hash-table :test 'equal))))

(defun streak--render-streaks (streaks)
  "Render each streak in STREAKS together into a single string."
  (let* ((now (streak--seconds-since-unix-epoch))
         (seconds-per-day 86400)
         (strings (mapcar (lambda (key)
                            (let* ((start (gethash key streaks))
                                   (fmt (cdr (assoc key streak-formatters)))
                                   (delta (/ (- now start) seconds-per-day)))
                              (cond (fmt (funcall fmt delta))
                                    ((string= "legacy" key) (format "%d" delta))
                                    (t (format "%c:%d" (string-to-char key) delta)))))
                          (hash-table-keys streaks))))
    (concat " " (string-join strings " ") " ")))

;;;###autoload
(defun streak-new (name)
  "Given the NAME of a new streak to track, add it to the streak file."
  (interactive "sName of new streak: ")
  (let ((streaks (streak--current-streaks))
        (now (streak--seconds-since-unix-epoch)))
    (if (gethash name streaks)
        (message "A streak by that name already exists.")
      (puthash name now streaks)
      (streak--write-streaks streaks)
      (streak-update))))

(defun streak--write-streaks (streaks)
  "Write the given STREAKS hashmap to the streak file."
  (let ((buffer (find-file-noselect streak-file))
        (json (json-serialize streaks)))
    (with-current-buffer buffer
      (delete-region (point-min) (point-max))
      (insert json)
      (save-buffer))))

;;;###autoload
(defun streak-reset ()
  "Mark the current time as the new start of an existing streak."
  (interactive)
  (let ((streaks (streak--current-streaks)))
    (if (not (hash-table-empty-p streaks))
        (when-let ((choice (completing-read "Streak to reset: " streaks)))
          (puthash choice (streak--seconds-since-unix-epoch) streaks)
          (streak--write-streaks streaks)
          (streak-update)))))

;;;###autoload
(defun streak-increment ()
  "Move a streak start back by 1 day, increasing the overall streak days."
  (interactive)
  (let ((streaks (streak--current-streaks)))
    (if (not (hash-table-empty-p streaks))
        (when-let* ((choice (completing-read "Streak to increment: " streaks))
                    (seconds-per-day 86400)
                    (new (- (gethash choice streaks) seconds-per-day)))
          (puthash choice new streaks)
          (streak--write-streaks streaks)
          (streak-update)))))

;;;###autoload
(defun streak-decrement ()
  "Move a streak start up by 1 day, decreasing the overall streak days."
  (interactive)
  (let ((streaks (streak--current-streaks)))
    (if (not (hash-table-empty-p streaks))
        (when-let* ((choice (completing-read "Streak to decrement: " streaks))
                    (seconds-per-day 86400)
                    (new (+ (gethash choice streaks) seconds-per-day)))
          (puthash choice new streaks)
          (streak--write-streaks streaks)
          (streak-update)))))

;;;###autoload
(defun streak-update ()
  "Reread the streak file and update the mode line."
  (interactive)
  (setq streak--streak-message (streak--current)))

(provide 'streak)
;;; streak.el ends here
