;;; op-export.el --- Publication related functions required by org-page

;; Copyright (C) 2012, 2013 Kelvin Hu

;; Author: Kelvin Hu <ini DOT kelvin AT gmail DOT com>
;; Keywords: convenience
;; Homepage: https://github.com/kelvinh/org-page
;; Version: 0.3

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; org source publication related functions

;;; Code:

(require 'format-spec)

(defun op/publish-changes (all-list change-plist pub-root-dir)
  "This function is for:
1. publish changed org files to html
2. delete html files which are relevant to deleted org files (NOT implemented)
3. update index page
4. regenerate tag pages.
ALL-LIST contains paths of all org files, CHANGE-PLIST contains two properties,
one is :update for files to be updated, another is :delete for files to be
deleted. PUB-ROOT-DIR is the root publication directory."
  (let* ((upd-list (plist-get change-plist :update))
         (del-list (plist-get change-plist :delete))
         visiting file-buffer file-attr-list)
    (op/update-default-template-parameters) ;; ensure default parameters are newest
    (when (or upd-list del-list)
      (mapc
       #'(lambda (org-file)
           (setq visiting (find-buffer-visiting org-file))
           (with-current-buffer (setq file-buffer
                                      (or visiting (find-file org-file)))
             (setq file-attr-list (cons (op/get-org-file-options
                                         pub-root-dir
                                         (member org-file upd-list))
                                        file-attr-list))
             (when (member org-file upd-list)
               (op/publish-modified-file (car file-attr-list)))
             (when (member org-file del-list)
               (op/handle-deleted-file org-file)))
           (or visiting (kill-buffer file-buffer)))
       all-list)
      (unless (member
               (expand-file-name "index.org" op/repository-directory)
               all-list)
        (op/generate-default-index file-attr-list pub-root-dir))
      (unless (member ; TODO customization
               (expand-file-name "about.org" op/repository-directory)
               all-list)
        (op/generate-default-about pub-root-dir))
      (op/update-category-index file-attr-list pub-root-dir 'blog)
      (op/update-category-index file-attr-list pub-root-dir 'wiki)
      (op/update-tags file-attr-list pub-root-dir))))

(defun op/get-org-file-options (pub-root-dir do-pub)
  "Retrieve all needed options for org file opened in current buffer.
PUB-ROOT-DIR is the root directory of published files, if DO-PUB is t, the
content of the buffer will be converted into html."
  (let* ((filename (buffer-file-name))
         (attr-plist `(:title ,(or (op/read-org-option "TITLE")
                                   "Untitled")
                       :author ,(or (op/read-org-option "AUTHOR")
                                    user-full-name
                                    "Unknown Author")
                       :email ,(or (op/read-org-option "EMAIL")
                                   user-mail-address
                                   "Unknown Email")
                       :date ,(or (op/read-org-option "DATE")
                                  (format-time-string "%Y-%m-%d"))
                       :keywords ,(op/read-org-option "KEYWORDS")
                       :description ,(op/read-org-option "DESCRIPTION")
                       :site-main-title ,op/site-main-title
                       :site-sub-title ,op/site-sub-title
                       :github ,op/personal-github-link
                       :site-domain ,(if (and
                                          op/site-domain
                                          (string-match
                                           "\\`https?://\\(.*[a-zA-Z]\\)/?\\'"
                                           op/site-domain))
                                         (match-string 1 op/site-domain)
                                       op/site-domain)
                       :mod-date ,(if (not filename)
                                      (format-time-string "%Y-%m-%d")
                                    (or (op/git-last-change-date
                                         op/repository-directory
                                         filename)
                                        (format-time-string
                                         "%Y-%m-%d"
                                         (nth 5 (file-attributes filename)))))
                       :tags ,nil
                       :disqus-shortname ,op/personal-disqus-shortname
                       :google-analytics ,(boundp
                                           'op/personal-google-analytics-id)
                       :google-analytics-id ,op/personal-google-analytics-id
                       :creator-info ,org-html-creator-string
                       :content ,nil))
         tags category cat-config)
    (plist-put attr-plist :page-title (concat (plist-get attr-plist :title)
                                              " - "
                                              op/site-main-title))
    (setq tags (op/read-org-option "TAGS"))
    (when tags
      (plist-put
       attr-plist :tags (delete "" (mapcar 'trim-string
                                           (split-string tags "[;,]+" t)))))
    (plist-put
     attr-plist :tag-links
     (if (not tags) "N/A"
       (mapconcat #'(lambda (tag-name)
                      (mustache-render
                       "<a href=\"{{link}}\">{{name}}</a>"
                       (ht ("link" (op/generate-tag-uri tag-name))
                           ("name" tag-name))))
                  tags ", ")))
    (setq category (funcall (or op/retrieve-category-function
                                op/get-file-category)
                            filename))
    (plist-put attr-plist :category category)
    (setq cat-config (cdr (or (assoc category op/category-config-alist)
                              (assoc "blog" op/category-config-alist))))
    (plist-put attr-plist :show-meta (plist-get cat-config :show-meta))
    (plist-put attr-plist :show-comment (plist-get cat-config :show-comment))
    (plist-put attr-plist :uri (funcall (plist-get cat-config :uri-generator)
                                        (plist-get cat-config :uri-template)
                                        (plist-get attr-plist :date)
                                        (plist-get attr-plist :title)))
    (plist-put attr-plist :disqus-id (plist-get attr-plist :uri))
    (plist-put attr-plist :disqus-url (concat
                                       (replace-regexp-in-string
                                        "/?$" "" op/site-domain)
                                       (plist-get attr-plist :disqus-id)))
    (plist-put attr-plist :pub-dir (file-name-as-directory
                                    (concat
                                     (file-name-as-directory pub-root-dir)
                                     (replace-regexp-in-string
                                      "\\`/" ""
                                      (plist-get attr-plist :uri)))))
    (when do-pub
      (plist-put attr-plist :content (org-export-as 'html nil nil t nil)))))

(defun op/read-org-option (option)
  "Read option value of org file opened in current buffer.
e.g:
#+TITLE: this is title
will return \"this is title\" if OPTION is \"TITLE\""
  (let ((match-regexp (org-make-options-regexp `(,option))))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward match-regexp nil t)
        (match-string-no-properties 2 nil)))))

(defun op/generate-uri (default-uri-template creation-date title)
  "Generate URI of org file opened in current buffer. It will be firstly created
by #+URI option, if it is nil, DEFAULT-URI-TEMPLATE will be used to generate the
uri. If CREATION-DATE is nil, current date will be used. The uri template option
can contain following parameters:
%y: year of creation date
%m: month of creation date
%d: day of creation date
%t: title of current buffer"
  (let ((uri-template (or (op/read-org-option "URI")
                          default-uri-template))
        (date-list (split-string (if creation-date
                                     (fix-timestamp-string creation-date)
                                   (format-time-string "%Y-%m-%d"))
                                 "-"))
        (encoded-title (convert-string-to-path title)))
    (format-spec uri-template `((?y . ,(car date-list))
                                (?m . ,(cadr date-list))
                                (?d . ,(caddr date-list))
                                (?t . ,encoded-title)))))

(defun op/get-file-category (org-file)
  "Get org file category presented by ORG-FILE. This is the default function
used to get a file's category, see `op/retrieve-category-function'.
How to judge a file's category is based on its name and its root folder name
under `op/repository-directory'."
  (cond ((or (not org-file)
             (string= (file-name-directory (expand-file-name org-file))
                      op/repository-directory)) "blog")
        ((string= (expand-file-name "index.org" op/repository-directory)
                  (expand-file-name org-file)) "index")
        ((string= (expand-file-name "about.org" op/repository-directory)
                  (expand-file-name org-file)) "about")
        (t (car (split-string (file-relative-name (expand-file-name org-file)
                                                  op/repository-directory)
                              "[/\\\\]+")))))

;;; this function is now deprecated
(defun op/get-inbuffer-extra-options ()
  "Read extra options(defined by ourselves) in current buffer, include:
1. modification date (read from git last commit date, current date if current
buffer is a temp buffer)
2. tags (read from #+TAGS property)
3. uri (read from #+URI property)
4. category ('blog, 'wiki, 'about, 'index or 'none, distinguished by their name
or root folder name under `op/repository-directory', 'none if current buffer is
a temp buffer)"
  (let* ((filename (buffer-file-name))
         (attr-plist `(:mod-date ,(format-time-string "%Y-%m-%d") :tags ,nil))
         tags)
    (setq tags (op/read-org-option "TAGS"))
    (when tags
      (plist-put
       attr-plist :tags (delete "" (mapcar 'trim-string
                                           (split-string tags "[:,]+" t))))) ;; TODO customization
    (when filename
      (plist-put
       attr-plist :mod-date
       (or (op/git-last-change-date op/repository-directory filename)
           (format-time-string "%Y-%m-%d" (nth 5 (file-attributes filename))))))
    (plist-put attr-plist :category (op/get-file-category filename))
    (plist-put attr-plist :uri (op/generate-uri
                                (op/read-org-option "URI")
                                (op/read-org-option "DATE")
                                (op/read-org-option "TITLE")
                                (plist-get attr-plist :category)))))

(defun op/publish-modified-file (attr-plist)
  "Publish org file opened in current buffer. ATTR-PLIST is the attribute
property list of current file.
NOTE: if :content of ATTR-PLIST is nil, the publication will be skipped."
  (when (plist-get attr-plist :content)
    (let ((pub-dir (plist-get attr-plist :pub-dir))
          (mustache-partial-paths `(,op/template-directory)))
      (unless (file-directory-p pub-dir)
        (mkdir pub-dir t))
      (string-to-file (mustache-render op/page-template
                                       (ht-from-plist attr-plist))
                      (concat pub-dir "index.html")))))

(defun op/handle-deleted-file (org-file-path)
  "TODO: add logic for this function, maybe a little complex."
  )

(defun op/rearrange-category-sorted (file-attr-list)
  "Rearrange and sort attribute property lists from FILE-ATTR-LIST. Rearrange
according to category, and sort according to :sort-by property defined in
`op/category-config-alist', if category is not in `op/category-config-alist',
the default 'blog' category will be used. For sorting, later lies headmost."
  (let (cat-alist cat-list)
    (mapc
     #'(lambda (plist)
         (setq cat-list (cdr (assoc (plist-get plist :category) cat-alist)))
         (if cat-list
             (nconc cat-list (list plist))
           (setq cat-alist (cons (cons (plist-get plist :category)
                                       (list plist))
                                 cat-alist))))
     file-attr-list)
    (mapcar
     #'(lambda (cell)
         (setcdr
          cell
          (sort (cdr cell)
                #'(lambda (plist1 plist2)
                    (<= (compare-standard-date
                         (fix-timestamp-string
                          (plist-get
                           plist1
                           (plist-get
                            (cdr (or (assoc (plist-get plist1 :category)
                                            op/category-config-alist)
                                     (assoc "blog"
                                            op/category-config-alist)))
                            :sort-by)))
                         (fix-timestamp-string
                          (plist-get
                           plist2
                           (plist-get
                            (cdr (or (assoc (plist-get plist2 :category)
                                            op/category-config-alist)
                                     (assoc "blog"
                                            op/category-config-alist)))
                            :sort-by))))
                        0)))))
     cat-alist)))

(defun op/update-category-index (file-attr-list pub-base-dir category)
  "Update index page of category 'blog or 'wiki. FILE-ATTR-LIST is the list of
all file attribute property lists. PUB-BASE-DIR is the root publication
directory. CATEGORY is 'blog or 'wiki, 'blog if other values."
  (let* ((cat (if (memq category '(blog wiki)) category 'blog))
         (sort-alist '((blog . :date) (wiki . :mod-date)))
         (cat-list (op/filter-category-sorted file-attr-list cat))
         (pub-dir (file-name-as-directory
                   (expand-file-name (symbol-name cat) pub-base-dir))))
    (with-current-buffer (get-buffer-create op/temp-buffer-name)
      (erase-buffer)
      (insert "#+TITLE: " (capitalize (symbol-name cat)) " Index" "\n")
      (insert "#+URI: /" (symbol-name cat) "/\n")
      (insert "#+OPTIONS: *:nil" "\n\n")
      (mapc '(lambda (attr-plist)
               (insert " - "
                       (fix-timestamp-string
                        (org-element-interpret-data
                         (plist-get attr-plist (cdr (assq cat sort-alist)))))
                       "\\nbsp\\nbsp»\\nbsp\\nbsp"
                       "@@html:<a href=\"" (plist-get attr-plist :uri) "\">"
                       (org-element-interpret-data
                        (plist-get attr-plist :title)) "</a>@@" "\n"))
            cat-list)
      (unless (file-directory-p pub-dir)
        (mkdir pub-dir t))
      (string-to-file
       (mustache-render op/page-template
                        (op/compose-template-parameters
                         (org-combine-plists
                          (org-export--get-inbuffer-options 'html)
                          (op/get-inbuffer-extra-options))
                         (org-export-as 'html nil nil t nil)))
       (concat pub-dir "index.html")))))

(defun op/generate-default-index (file-attr-list pub-base-dir)
  "Generate default index page, only if index.org does not exist. FILE-ATTR-LIST
is the list of all file attribute property lists. PUB-BASE-DIR is the root
publication directory."
  (let* ((blog-list (op/filter-category-sorted file-attr-list 'blog))
         (wiki-list (op/filter-category-sorted file-attr-list 'wiki))
         (cat-alist `((blog . ,blog-list) (wiki . ,wiki-list)))
         category plist-key)
    (with-current-buffer (get-buffer-create op/temp-buffer-name)
      (erase-buffer)
      (insert "#+TITLE: Index" "\n")
      (insert "#+URI: /" "\n")
      (insert "#+OPTIONS: *:nil" "\n\n")
      (mapc
       '(lambda (cell)
          (setq category (symbol-name (car cell)))
          (setq plist-key
                (if (string= category "wiki") :mod-date :date))
          (insert " - " category "\n")
          (mapc '(lambda (attr-plist)
                   (insert "   - " (fix-timestamp-string
                                    (org-element-interpret-data
                                     (plist-get attr-plist plist-key)))
                           "\\nbsp\\nbsp»\\nbsp\\nbsp"
                           "@@html:<a href=\"" (plist-get attr-plist :uri) "\">"
                           (org-element-interpret-data
                            (plist-get attr-plist :title))
                           "</a>@@" "\n"))
                (cdr cell)))
       cat-alist)
      (string-to-file
       (mustache-render op/page-template
                        (op/compose-template-parameters
                         (org-combine-plists
                          (org-export--get-inbuffer-options 'html)
                          (op/get-inbuffer-extra-options))
                         (org-export-as 'html nil nil t nil)))
       (concat pub-base-dir "index.html")))))

(defun op/generate-default-about (pub-base-dir)
  "Generate default about page, only if about.org does not exist. PUB-BASE-DIR
is the root publication directory."
  (let ((author-name (or user-full-name "[author]"))
        (pub-dir (expand-file-name "about/" pub-base-dir)))
    (with-current-buffer (get-buffer-create op/temp-buffer-name)
      (erase-buffer)
      (insert "#+TITLE: About" "\n")
      (insert "#+URI: /about/" "\n\n")
      (insert (format "* About %s" author-name) "\n\n")
      (insert (format "I am [[https://github.com/kelvinh/org-page][org-page]], \
this site is generated by %s, and I provided a little help." author-name))
      (insert "\n\n")
      (insert (format "Since %s is a little lazy, he/she did not provide an \
about page, so I generated this page myself." author-name))
      (insert "\n\n")
      (insert "* About me(org-page)" "\n\n")
      (insert (format "[[https://github.com/kelvinh][Kelvin Hu]] is my \
creator, please [[mailto:%s][contact him]] if you find there is something need \
to improve, many thanks. :-)" (confound-email "ini.kelvin@gmail.com")))
      (string-to-file
       (mustache-render op/page-template
                        (op/compose-template-parameters
                         (org-combine-plists
                          (org-export--get-inbuffer-options 'html)
                          (op/get-inbuffer-extra-options))
                         (org-export-as 'html nil nil t nil)))
       (concat pub-dir "index.html")))))

(defun op/generate-tag-uri (tag-name)
  "Generate tag uri based on TAG-NAME."
  (concat "/tags/" (convert-string-to-path tag-name) "/"))

(defun op/update-tags (file-attr-list pub-base-dir)
  "Update tag pages. FILE-ATTR-LIST is the list of all file attribute property
lists. PUB-BASE-DIR is the root publication directory.
TODO: improve this function."
  (let ((tag-base-dir (expand-file-name "tags/" pub-base-dir))
        tag-alist tag-list tag-dir)
    (mapc
     '(lambda (attr-plist)
        (mapc
         '(lambda (tag-name)
            (setq tag-list (assoc tag-name tag-alist))
            (unless tag-list
              (add-to-list 'tag-alist (setq tag-list `(,tag-name))))
            (nconc tag-list (list attr-plist)))
         (plist-get attr-plist :tags)))
     file-attr-list)
    (with-current-buffer (get-buffer-create op/temp-buffer-name)
      (erase-buffer)
      (insert "#+TITLE: Tag Index" "\n")
      (insert "#+URI: /tags/" "\n")
      (insert "#+OPTIONS: *:nil" "\n\n")
      (mapc '(lambda (tag-list)
               (insert " - " "@@html:<a href=\""
                       (op/generate-tag-uri (car tag-list))
                       "\">" (car tag-list)
                       " (" (number-to-string (length (cdr tag-list))) ")"
                       "</a>@@" "\n"))
            tag-alist)
      (unless (file-directory-p tag-base-dir)
        (mkdir tag-base-dir t))
      (string-to-file
       (mustache-render op/page-template
                        (op/compose-template-parameters
                         (org-combine-plists
                          (org-export--get-inbuffer-options 'html)
                          (op/get-inbuffer-extra-options))
                         (org-export-as 'html nil nil t nil)))
       (concat tag-base-dir "index.html")))
    (mapc
     #'(lambda (tag-list)
         (with-current-buffer (get-buffer-create op/temp-buffer-name)
           (erase-buffer)
           (insert "#+TITLE: Tag: " (car tag-list) "\n")
           (insert "#+URI: " (op/generate-tag-uri (car tag-list)) "\n")
           (insert "#+OPTIONS: *:nil" "\n\n")
           (mapc #'(lambda (attr-plist)
                     (insert " - "
                             "@@html:<a href=\"" (plist-get attr-plist :uri) "\">"
                             (org-element-interpret-data
                              (plist-get attr-plist :title))
                             "</a>@@" "\n"))
                 (cdr tag-list))
           (setq tag-dir (file-name-as-directory
                          (concat tag-base-dir
                                  (convert-string-to-path (car tag-list)))))
           (unless (file-directory-p tag-dir)
             (mkdir tag-dir t))
           (string-to-file
            (mustache-render op/page-template
                             (op/compose-template-parameters
                              (org-combine-plists
                               (org-export--get-inbuffer-options 'html)
                               (op/get-inbuffer-extra-options))
                              (org-export-as 'html nil nil t nil)))
            (concat tag-dir "index.html"))))
     tag-alist)))

;; (defun op/kill-exported-buffer (export-buf-or-file)
;;   "Kill the exported buffer. This function is a snippet copied from
;; `org-publish-org-to'."
;;   (when (and (bufferp export-buf-or-file)
;;              (buffer-live-p export-buf-or-file))
;;     (set-buffer export-buf-or-file)
;;     (when (buffer-modified-p) (save-buffer))
;;     (kill-buffer export-buf-or-file)))


(provide 'op-export)

;;; op-export.el ends here
