(in-package :potato.core)

(declaim #.potato.common::*compile-decl*)

(defmacro define-conspack-encoders (class-name &body field-overrides)
  (let ((class (find-class class-name))
        (val-sym (gensym)))
    (closer-mop:finalize-inheritance class)
    `(progn
       (defmethod conspack:encode-object ((obj ,class-name) &key)
         (list ,@(loop
                    for slot in (closer-mop:class-slots class)
                    for slot-name = (closer-mop:slot-definition-name slot)
                    for override-definition = (find slot-name field-overrides :key #'car)
                    for slot-getter = `(slot-value obj ',(closer-mop:slot-definition-name slot))
                    collect `(cons ,(intern (symbol-name slot-name) "KEYWORD")
                                   ,(if override-definition
                                        `(funcall ,(second override-definition) ,slot-getter)
                                        slot-getter)))))
       (defmethod conspack:decode-object ((type (eql ',class-name)) vals &key)
         (let ((obj (allocate-instance (find-class ',class-name))))
           ,@(loop
                for slot in (closer-mop:class-slots class)
                for slot-name = (closer-mop:slot-definition-name slot)
                for override-definition = (find slot-name field-overrides :key #'car)
                for slot-setter = `(cdr ,val-sym)
                collect `(let ((,val-sym (assoc ,(intern (symbol-name slot-name) "KEYWORD") vals)))
                           (when ,val-sym (setf (slot-value obj ',slot-name)
                                                ,(if override-definition
                                                     `(funcall ,(third override-definition) ,slot-setter)
                                                     slot-setter)))))
           (initialize-instance obj)
           obj)))))

(define-conspack-encoders user)
(define-conspack-encoders persisted-user-session)
(define-conspack-encoders user-unread-channel-state)
(define-conspack-encoders user-unread-state-rabbitmq-message)
(define-conspack-encoders channel)
(define-conspack-encoders channel-users)
(define-conspack-encoders group)
(define-conspack-encoders display-config)
(define-conspack-encoders notification-keywords)
(define-conspack-encoders message
  (created-date (lambda (v) (if v (format-timestamp nil v) nil))
                (lambda (v) (if v (parse-timestamp v) nil)))
  (updated-date (lambda (v) (if v (format-timestamp nil v) nil))
                (lambda (v) (if v (parse-timestamp v) nil))))
(define-conspack-encoders message-updated
  (date (lambda (v) (if v (format-timestamp nil v) nil))
        (lambda (v) (if v (parse-timestamp v) nil))))
(define-conspack-encoders potato.email:mail-descriptor)
(define-conspack-encoders potato.user-notification:user-notification-state
  (potato.user-notification::email-sent-time (lambda (v) (if v (format-timestamp nil v) nil))
                                             (lambda (v) (if v (parse-timestamp v) nil))))
(define-conspack-encoders potato.core:domain-nickname)
(define-conspack-encoders potato.core::domain-config)
(define-conspack-encoders potato.core:channel-nickname)
(define-conspack-encoders potato.core::domain-user)
