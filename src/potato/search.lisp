(in-package :potato.search)

(declaim #.potato.common::*compile-decl*)

(define-handler-fn-login (search-test-screen "/search_test" nil ())
  (with-authenticated-user ()
    (lofn:with-parameters (group channel)
      (lofn:show-template-stream "search_test.tmpl" `((:channel . ,channel)
                                                      (:group . ,group))))))

(defun search-node->list (node)
  (loop
     for n across (dom:child-nodes node)
     collect (let* ((type (dom:node-name n))
                    (name (dom:get-attribute n "name"))
                    (value (string-case:string-case (type)
                             ("str" (value-by-xpath "text()" n))
                             ("date" (value-by-xpath "text()" n))
                             ("long" (parse-integer (value-by-xpath "text()" n)))
                             ("arr" nil))))
               (cons name value))))

(define-json-handler-fn-login (search-message-screen "/search_message" data nil ())
  (with-authenticated-user ()
    (let ((text (st-json:getjso "text" data))
          (channel-id (json-parse-null (st-json:getjso "channel" data)))
          (group-id (json-parse-null (st-json:getjso "group" data)))
          (star-only-p (let ((v (st-json:getjso "star_only" data)))
                         (if v (st-json:from-json-bool v) nil))))
      (check-type text string)
      (let* ((search-grouping (cond ((and channel-id group-id)
                                     (error "channel and group both specified"))
                                    ((and (null channel-id) (null group-id))
                                     (error "channel or group must be specified"))
                                    (group-id
                                     (let ((group (load-group-with-check group-id)))
                                       (format nil "group_id:\"~a\"" (group/id group))))
                                    (t
                                     (let ((channel (load-channel-with-check channel-id)))
                                       (format nil "channel_id:\"~a\"" (channel/id channel))))))
             (star-grouping (if star-only-p (format nil " AND star_user:\"~a\"" (user/id (current-user))) ""))
             (params `(("defType" . "edismax")
                       ("df" . "content")
                       ("f.from.qf" . "sender_name")
                       ("f.date.qf" . "created_date")
                       ("f.channel.qf" . "channel_name")
                       ("f.message.qf" . "content")
                       ("fq" . ,(format nil "potato_type:\"message\" AND ~a~a" search-grouping star-grouping))
                       ("hl" . "true")
                       ("hl.fl" . "content")
                       ("uf" . "from date message")))
             (res (cl-solr:query-noparse text :parameters params))
             (response-node (xpath:first-node (xpath:evaluate "/response/result[@name='response']" res)))
             (num-found (parse-integer (dom:get-attribute response-node "numFound")))
             (start (parse-integer (dom:get-attribute response-node "start")))
             (msgs (xpath:map-node-set->list #'search-node->list (xpath:evaluate "doc" response-node)))
             (hl (xpath:evaluate "/response/lst[@name='highlighting']/lst" res))
             (snippets (xpath:map-node-set->list (lambda (v)
                                                   (let ((message-id (dom:get-attribute v "name"))
                                                         (snippet (value-by-xpath "arr[@name='content']/str/text()" v :default-value nil)))
                                                     (list message-id snippet)))
                                                 hl)))
        (flet ((find-value (name msg)
                 (cdr (find name msg :key #'car :test #'equal))))
          (log:trace "Searching with text: ~s, params: ~s, results: ~s" text params msgs)
          (st-json:jso "num_found" num-found
                       "start" start
                       "messages"
                       (loop
                          for msg in msgs
                          for id = (find-value "id" msg)
                          for snippet-entry = (find id snippets :key #'car :test #'equal)
                          collect (st-json:jso "id" id
                                               "sender_name" (find-value "sender_name" msg)
                                               "sender_id" (find-value "sender_id" msg)
                                               "created_date" (find-value "created_date" msg)
                                               "content" (or (second snippet-entry)
                                                             (find-value "content" msg))))))))))
