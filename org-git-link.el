;;; org-git-link.el --- Provide org links to specific file version

;; Copyright (C) 2009  Reimar Finken

;; Author: Reimar Finken <reimar.finken@gmx.de>
;; Keywords: files, calendar, hypermedia

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distaributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; `org-git-link.el' defines two new link types. The `git' link
;; type is meant to be used in the typical scenario and mimics the
;; `file' link syntax as closely as possible. The `gitbare' link
;; type exists mostly for debugging reasons, but also allows e.g.
;; linking to files in a bare git repository for the experts.

;; * User friendy form
;;   [[git:/path/to/file::searchstring]]

;;   This form is the familiar from normal org file links
;;   including search options. However, its use is
;;   restricted to files in a working directory and does not
;;   handle bare repositories on purpose (see the bare form for
;;   that).

;;   The search string references a commit (a tree-ish in Git
;;   terminology). The two most useful types of search strings are

;;   - A symbolic ref name, usually a branch or tag name (e.g.
;;     master or nobelprize).
;;   - A ref followed by the suffix @ with a date specification
;;     enclosed in a brace pair (e.g. {yesterday}, {1 month 2
;;     weeks 3 days 1 hour 1 second ago} or {1979-02-26 18:30:00})
;;     to specify the value of the ref at a prior point in time
;;
;; * Bare git form
;;   [[gitbare[:$ACCESS_POINT]:$GIT_DIR::$OBJECT]]
;;
;;    This is the more bare metal version, which gives the user most
;;    control. For the default access-point (localhost) it directly
;;    translates to the git command
;;    git --no-pager --git-dir=$GIT_DIR show $OBJECT
;;    Using this version one can also view files from a bare git
;;    repository. For detailed information on how to specify an
;;    object, see the man page of `git-rev-parse' (section
;;    SPECIFYING REVISIONS). A specific blob (file) can be
;;    specified by a suffix clolon (:) followed by a path.

;;; Code:

(require 'org)
(defcustom org-git-program "git"
  "Name of the git executable used to follow git links."
  :type '(string)
  :group 'org)
(defcustom org-access-program "ssh"
  "Name of the executable used to follow non-local links."
  :type '(string)
  :group 'org)


(defcustom org-git-store-activate 'ask
  "*Variable controlling whether org-store-link stores a git link.
  `t' means always store a git link (this might override other
  possibilities, such as linking to org entries by id). `nil'
  means never store git links. The symbol `ask' means ask the
  user whether a link should be stored."
  :type '(choice (const :tag "Always" t)
                (const :tag "Never" nil)
                (const :tag "Ask" ask))
  :group 'org)

;; org link functions
;; bare git link
(org-add-link-type "gitbare" 'org-gitbare-open)

(defun org-gitbare-open (str)
  (let* ((strlist (org-git-split-string str))
         (access-point (first strlist))
         (gitdir (second strlist))
         (object (third strlist)))
    (org-git-open-file-internal access-point gitdir object)))


(defun org-git-open-file-internal (access-point gitdir object)
  (let* ((gitdir (if (string= access-point "localhost")
                     (expand-file-name (substitute-in-file-name gitdir))
                   gitdir))
         (sha (org-git-blob-sha access-point gitdir object))
         (tmpdir (concat temporary-file-directory "org-git-" sha))
         (filename (org-git-link-filename object))
         (tmpfile (expand-file-name filename tmpdir)))
    (unless (file-readable-p tmpfile)
      (make-directory tmpdir)
      (with-temp-file tmpfile
        (org-git-show access-point gitdir object (current-buffer))))
    (org-open-file tmpfile)
    (set-buffer (get-file-buffer tmpfile))
    (setq buffer-read-only t)))

;; user friendly link
(org-add-link-type "git" 'org-git-open)

(require 'cl) ;; needed for assert macro

(defun org-git-open (str)
  (let* ((strlist (org-git-split-string str))
         (access-point (first strlist))
         (filepath (second strlist))
         (commit (third strlist))
         (dirlist (org-git-find-gitdir filepath))
         (gitdir (first dirlist))
         (relpath (second dirlist)))
    (assert (string= access-point "localhost"))
    (org-git-open-file-internal access-point gitdir (concat commit ":" relpath))))


;; Utility functions (file names etc)

(defun org-git-split-dirpath (dirpath)
  "Given a directory name, return '(dirname basname)"
  (let ((dirname (file-name-directory (directory-file-name dirpath)))
        (basename (file-name-nondirectory (directory-file-name dirpath))))
    (list dirname basename)))

;; finding the git directory
(defun org-git-find-gitdir (path)
  "Given a file (not necessarily existing) file path, return the
  a pair (gitdir relpath), where gitdir is the path to the first
  .git subdirectory found updstream and relpath is the rest of
  the path. Example: (org-git-find-gitdir
  \"~/gitrepos/foo/bar.txt\") returns
  '(\"/home/user/gitrepos/.git\" \"foo/bar.txt\"). When not in a git repository, return nil."
  (let ((dir (file-name-directory path))
        (relpath (file-name-nondirectory path)))
    (catch 'toplevel
      (while (not (file-exists-p (expand-file-name ".git" dir)))
        (let ((dirlist (org-git-split-dirpath dir)))
          (when (string= (second dirlist) "") ; at top level
            (throw 'toplevel nil))
          (setq dir (first dirlist)
                relpath (concat (file-name-as-directory (second dirlist)) relpath))))
      (list (expand-file-name ".git" dir) relpath))))


(if (featurep 'xemacs)
    (defalias 'org-git-gitrepos-p 'org-git-find-gitdir)
  (defalias 'org-git-gitrepos-p 'org-git-find-gitdir
  "Return non-nil if path is in git repository"))

;; splitting the link string

;; Both link open functions are called with a string of
;; consisting of two parts separated by a double colon (::).
(defun org-git-split-string (str)
  "Given a string of the form \"str1:str2::str3\", return a list of
  three substrings \'(\"str1\" \"str2\" \"str3\"). If the double colon is
missing, take str2 to be the empty string. If the single colon is missing, take
str1 to be \"localhost\"."
  (let* ((strlist (split-string str "::"))
         (strlist2 (split-string (car strlist) ":"))
         (strlist3 (cond
                    ((= 1 (length strlist2))
                     (list "localhost" (car strlist2)))
                    ((= 2 (length strlist2))
                     strlist2)))
         )
    (cond ((= 1 (length strlist))
           (append strlist3 '("")))
          ((= 2 (length strlist))
           (append strlist3 (cdr strlist)))
          (t (error "org-git-split-string: only one :: allowed: %s" str)))))

;; finding the file name part of a commit
(defun org-git-link-filename (str)
  "Given an object description (see the man page of
  git-rev-parse), return the nondirectory part of the referenced
  filename, if it can be extracted. Otherwise, return a valid
  filename."
  (let* ((match (and (string-match "[^:]+$" str)
                     (match-string 0 str)))
         (filename (and match (file-name-nondirectory match)))) ;extract the final part without slash
    filename))

;; creating a link
(defun org-git-create-searchstring (branch timestring)
  (concat branch "@{" timestring "}"))


(defun org-git-create-git-link (file)
  "Create git link part to file at specific time"
  (interactive "FFile: ")
  (let* ((gitdir (first (org-git-find-gitdir file)))
         (branchname (org-git-get-current-branch gitdir))
         (timestring (format-time-string "%Y-%m-%d" (current-time))))
    (org-make-link "git:" file "::" (org-git-create-searchstring branchname timestring))))

(defun org-git-store-link ()
  "Store git link to current file."
  (let ((file (buffer-file-name)))
    (when (and file (org-git-gitrepos-p file) ; are we actually responsible
               (or (eq org-git-store-activate t)
                   (and (eq org-git-store-activate 'ask) (y-or-n-p "Create git link? "))))
        (org-store-link-props
         :type "git"
         :link (org-git-create-git-link (abbreviate-file-name file))))))

(add-hook 'org-store-link-functions 'org-git-store-link)

(defun org-git-insert-link-interactively (file searchstring &optional description)
  (interactive "FFile: \nsSearch string: \nsDescription: ")
  (insert (org-make-link-string (org-make-link "git:" file "::" searchstring) description)))

;; Calling git
(defun org-git-show (access-point gitdir object buffer)
  "Show the output of git --git-dir=gitdir show object in buffer."
  (unless
      (zerop (if (string= access-point "localhost")
                 (call-process org-git-program nil buffer nil
                               "--no-pager" (concat "--git-dir=" gitdir) "show"
                               object)
               (call-process org-access-program nil buffer nil
                             access-point (concat "git " "--no-pager " (concat
                                                                        "--git-dir="
                                                                        gitdir)
                                                  " show "  object)))
             )
    (error "git error: %s " (save-excursion (set-buffer buffer)
                                            (buffer-string)))))

(defun org-git-blob-sha (access-point gitdir object)
  "Return sha of the referenced object"
    (with-temp-buffer
      (if (zerop (if (string= access-point "localhost")
                     (call-process org-git-program nil t nil
                                   "--no-pager" (concat "--git-dir=" gitdir)
                                   "rev-parse" object)
                   (call-process org-access-program nil t nil
                                 access-point (concat "git " "--no-pager "
                                                      (concat "--git-dir="
                                                              gitdir)
                                   " rev-parse " object)))
           )
          (buffer-substring (point-min) (1- (point-max))) ; to strip off final newline
        (error "git error: %s " (buffer-string)))))

(defun org-git-get-current-branch (gitdir)
  "Return the name of the current branch."
  (with-temp-buffer
    (if (not (zerop (call-process org-git-program nil t nil
                                  "--no-pager" (concat "--git-dir=" gitdir) "symbolic-ref" "-q" "HEAD")))
        (error "git error: %s " (buffer-string))
      (goto-char (point-min))
      (if (looking-at "^refs/heads/")   ; 11 characters
          (buffer-substring 12 (1- (point-max))))))) ; to strip off final newline

(provide 'org-git-link)
;;; org-git-link.el ends here
