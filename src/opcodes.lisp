(in-package :6502)

;;;; REFERENCES:
;; http://www.obelisk.demon.co.uk/6502/reference.html
;; http://www.6502.org/tutorials/6502opcodes.html
;; http://nesdev.parodius.com/6502.txt
;; https://github.com/mnaberez/py65/blob/master/src/py65/devices/mpu6502.py

;;;; DESIGN:
;; Why methods and a case instead of functions inline in the case?
;; Well, now we can use :around methods and the MOP to be awesome/crazy.
;; Plus who wants one big case statement for a CPU? Ugh. Abstract!
;; Performance is less interesting than cool features and crazy hacks.
;; Optimize later! See Frodo redpill + ICU64 for an example of what's possible.
;; Worth using sb-sprof sampling profiler to find low hanging fruit.

(defopcode adc (:docs "Add to Accumulator with Carry")
    ((#x61 6 2 'indirect-x)
     (#x65 3 2 'zero-page)
     (#x69 2 2 'immediate)
     (#x6d 4 3 'absolute)
     (#x71 5 2 'indirect-y)
     (#x75 4 2 'zero-page-x)
     (#x79 4 3 'absolute-y)
     (#x7d 4 3 'absolute-x))
  ; TODO: This is a naive implementation. Have a look at py6502's opADC.
  (let ((result (+ (cpu-ar cpu) (funcall mode cpu) (status-bit :carry cpu))))
    (setf (cpu-ar cpu) result)
    (update-flags result cpu '(:carry :overflow :negative :zero))))

(defopcode and (:docs "And with Accumulator")
    ((#x21 6 2 'indirect-x)
     (#x25 3 2 'zero-page)
     (#x29 2 2 'immediate)
     (#x2d 4 3 'absolute)
     (#x31 5 2 'indirect-y)
     (#x35 4 2 'zero-page-x)
     (#x39 4 3 'absolute-y)
     (#x3d 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (logand (cpu-ar cpu) (funcall mode cpu)))))
    (set-flags-nz cpu result)))

(defopcode asl (:docs "Arithmetic Shift Left" :raw t)
    ((#x06 5 2 'zero-page)
     (#x0a 2 1 'accumulator)
     (#x0e 6 3 'absolute)
     (#x16 6 2 'zero-page-x)
     (#x1e 7 3 'absolute-x))
  (set-flags-if cpu :carry (lambda () (logbitp 7 (funcall mode cpu))))
  (let ((result (wrap-byte (ash (funcall mode cpu) 1))))
    (set-flags-nz cpu result)
    (funcall setf-form result)))

(defopcode bcc (:docs "Branch on Carry Clear" :track-pc nil)
    ((#x90 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :carry cpu))) cpu))

(defopcode bcs (:docs "Branch on Carry Set" :track-pc nil)
    ((#xb0 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :carry cpu))) cpu))

(defopcode beq (:docs "Branch if Equal" :track-pc nil)
    ((#xf0 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :zero cpu))) cpu))

(defopcode bit (:docs "Test Bits in Memory with Accumulator")
    ((#x24 3 2 'zero-page)
     (#x2c 4 3 'absolute))
  (let ((result (funcall mode cpu)))
    (set-flags-if cpu :zero (lambda () (zerop (logand (cpu-ar cpu) result)))
                  :negative (lambda () (logbitp 7 result))
                  :overflow (lambda () (logbitp 6 result)))))

(defopcode bmi (:docs "Branch on Negative Result" :track-pc nil)
    ((#x30 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :negative cpu))) cpu))

(defopcode bne (:docs "Branch if Not Equal" :track-pc nil)
    ((#xd0 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :zero cpu))) cpu))

(defopcode bpl (:docs "Branch on Positive Result" :track-pc nil)
    ((#x10 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :negative cpu))) cpu))

(defopcode brk (:docs "Force Break")
    ((#x00 7 1 'implied))
  (let ((pc (wrap-word (1+ (cpu-pc cpu)))))
    (stack-push-word pc cpu)
    (setf (status-bit :break cpu) 1)
    (stack-push (cpu-sr cpu) cpu)
    (setf (status-bit :interrupt cpu) 1)
    (setf (cpu-pc cpu) (get-word #xfffe))))

(defopcode bvc (:docs "Branch on Overflow Clear" :track-pc nil)
    ((#x50 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :overflow cpu))) cpu))

(defopcode bvs (:docs "Branch on Overflow Set" :track-pc nil)
    ((#x70 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :overflow cpu))) cpu))

(defopcode clc (:docs "Clear Carry Flag")
    ((#x18 2 1 'implied))
  (setf (status-bit :carry cpu) 0))

(defopcode cld (:docs "Clear Decimal Flag")
    ((#xd8 2 1 'implied))
  (setf (status-bit :decimal cpu) 0))

(defopcode cli (:docs "Clear Interrupt Flag")
    ((#x58 2 1 'implied))
  (setf (status-bit :interrupt cpu) 0))

(defopcode clv (:docs "Clear Overflow Flag")
    ((#xb8 2 1 'implied))
  (setf (status-bit :overflow cpu) 0))

(defopcode cmp (:docs "Compare Memory with Accumulator")
    ((#xc1 6 2 'indirect-x)
     (#xc5 3 2 'zero-page)
     (#xc9 2 2 'immediate)
     (#xcd 4 3 'absolute)
     (#xd1 5 2 'indirect-y)
     (#xd5 4 2 'zero-page-x)
     (#xd9 4 3 'absolute-y)
     (#xdd 4 3 'absolute-x))
  (let ((result (- (cpu-ar cpu) (funcall mode cpu))))
    ; TODO: Is :carry correct for the Compare Opcodes?
    (set-flags-if cpu :carry (lambda () (plusp result)))
    (set-flags-nz cpu result)))

(defopcode cpx (:docs "Compare Memory with X register")
    ((#xe0 2 2 'immediate)
     (#xe4 3 2 'zero-page)
     (#xec 4 3 'absolute))
  (let ((result (- (cpu-xr cpu) (funcall mode cpu))))
    (set-flags-if cpu :carry (lambda () (plusp result)))
    (set-flags-nz cpu result)))

(defopcode cpy (:docs "Compare Memory with Y register")
    ((#xc0 2 2 'immediate)
     (#xc4 3 2 'zero-page)
     (#xcc 4 3 'absolute))
  (let ((result (- (cpu-yr cpu) (funcall mode cpu))))
    (set-flags-if cpu :carry (lambda () (plusp result)))
    (set-flags-nz cpu result)))

(defopcode dec (:docs "Decrement Memory")
    ((#xc6 5 2 'zero-page)
     (#xce 6 3 'absolute)
     (#xd6 6 2 'zero-page-x)
     (#xde 7 3 'absolute-x))
  (let ((result (wrap-byte (1- (funcall mode cpu)))))
    (funcall setf-form result)
    (set-flags-nz cpu result)))

(defopcode dex (:docs "Decrement X register")
    ((#xca 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (wrap-byte (1- (cpu-xr cpu))))))
    (set-flags-nz cpu result)))

(defopcode dey (:docs "Decrement Y register")
    ((#x88 2 1 'implied))
  (let ((result (setf (cpu-yr cpu) (wrap-byte (1- (cpu-yr cpu))))))
    (set-flags-nz cpu result)))

(defopcode eor (:docs "Exclusive OR with Accumulator")
    ((#x41 6 2 'indirect-x)
     (#x45 3 2 'zero-page)
     (#x49 2 2 'immediate)
     (#x4d 4 3 'absolute)
     (#x51 5 2 'indirect-y)
     (#x55 4 2 'zero-page-x)
     (#x59 4 3 'absolute-y)
     (#x5d 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (logxor (funcall mode cpu) (cpu-ar cpu)))))
    (set-flags-nz cpu result)))

(defopcode inc (:docs "Increment Memory")
    ((#xe6 5 2 'zero-page)
     (#xee 6 3 'absolute)
     (#xf6 6 2 'zero-page-x)
     (#xfe 7 3 'absolute-x))
  (let ((result (wrap-byte (1+ (funcall mode cpu)))))
    (funcall setf-form result)
    (set-flags-nz cpu result)))

(defopcode inx (:docs "Increment X register")
    ((#xe8 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (wrap-byte (1+ (cpu-xr cpu))))))
    (set-flags-nz cpu result)))

(defopcode iny (:docs "Increment Y register")
    ((#xc8 2 1 'implied))
  (let ((result (setf (cpu-yr cpu) (wrap-byte (1+ (cpu-yr cpu))))))
    (set-flags-nz cpu result)))

(defopcode jmp (:docs "Jump Unconditionally" :raw t :track-pc nil)
    ((#x4c 3 3 'absolute)
     (#x6c 5 3 'indirect))
  (setf (cpu-pc cpu) (funcall mode cpu)))

(defopcode jsr (:docs "Jump to Subroutine" :raw t :track-pc nil)
    ((#x20 6 3 'absolute))
  (stack-push-word (wrap-word (1+ (cpu-pc cpu))) cpu)
  (setf (cpu-pc cpu) (get-word (funcall mode cpu))))

(defopcode lda (:docs "Load Accumulator from Memory")
    ((#xa1 6 2 'indirect-x)
     (#xa5 3 2 'zero-page)
     (#xa9 2 2 'immediate)
     (#xad 4 3 'absolute)
     (#xb1 5 2 'indirect-y)
     (#xb5 4 2 'zero-page-x)
     (#xb9 4 3 'absolute-y)
     (#xbd 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (funcall mode cpu))))
    (set-flags-nz cpu result)))

(defopcode ldx (:docs "Load X register from Memory")
    ((#xa2 2 2 'immediate)
     (#xa6 3 2 'zero-page)
     (#xae 4 3 'absolute)
     (#xb6 4 2 'zero-page-y)
     (#xbe 4 3 'absolute-y))
  (let ((result (setf (cpu-xr cpu) (funcall mode cpu))))
    (set-flags-nz cpu result)))

(defopcode ldy (:docs "Load Y register from Memory")
    ((#xa0 2 2 'immediate)
     (#xa4 3 2 'zero-page)
     (#xac 4 3 'absolute)
     (#xbc 4 3 'absolute-x)
     (#xb4 4 2 'zero-page-x))
  (let ((result (setf (cpu-yr cpu) (funcall mode cpu))))
    (set-flags-nz cpu result)))

(defopcode lsr (:docs "Logical Shift Right" :raw t)
    ((#x46 5 2 'zero-page)
     (#x4a 2 1 'accumulator)
     (#x4e 6 3 'absolute)
     (#x56 6 2 'zero-page-x)
     (#x5e 7 3 'absolute-x))
  (set-flags-if cpu :carry (lambda () (logbitp 0 (funcall mode cpu))))
  (let ((result (ash (get-byte (funcall mode cpu)) -1)))
    (funcall setf-form result)
    (set-flags-nz cpu result)))

(defopcode nop (:docs "No Operation")
    ((#xea 2 1 'implied))
  nil)

(defopcode ora (:docs "Bitwise OR with Accumulator")
    ((#x01 6 2 'indirect-x)
     (#x05 3 2 'zero-page)
     (#x09 2 2 'immediate)
     (#x0d 4 3 'absolute)
     (#x11 5 2 'indirect-y)
     (#x15 4 2 'zero-page-x)
     (#x19 4 3 'absolute-y)
     (#x1d 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (logior (cpu-ar cpu) (funcall mode cpu)))))
    (set-flags-nz cpu result)))

(defopcode pha (:docs "Push Accumulator")
    ((#x48 3 1 'implied))
  (stack-push (cpu-ar cpu) cpu))

(defopcode php (:docs "Push Processor Status")
    ((#x08 3 1 'implied))
  (stack-push (cpu-sr cpu) cpu))

(defopcode pla (:docs "Pull Accumulator from Stack")
    ((#x68 4 1 'implied))
  (let ((result (setf (cpu-ar cpu) (stack-pop cpu))))
    (set-flags-nz cpu result)))

(defopcode plp (:docs "Pull Processor Status from Stack")
    ((#x28 4 1 'implied))
  (setf (cpu-sr cpu) (stack-pop cpu)))

(defopcode rol (:docs "Rotate Left")
    ((#x2a 2 1 'accumulator)
     (#x26 5 2 'zero-page)
     (#x2e 6 3 'absolute)
     (#x36 6 2 'zero-page-x)
     (#x3e 7 3 'absolute-x))
  (set-flags-if cpu :carry (lambda () (logbitp 7 (funcall mode cpu))))
  (let ((result (wrap-byte (rotate-byte (funcall mode cpu) 1))))
    (funcall setf-form result)
    (set-flags-nz cpu result)))

(defopcode ror (:docs "Rotate Right")
    ((#x66 5 2 'zero-page)
     (#x6a 2 1 'accumulator)
     (#x6e 6 3 'absolute)
     (#x76 6 2 'zero-page-x)
     (#x7e 7 3 'absolute-x))
  (set-flags-if cpu :carry (lambda () (logbitp 0 (funcall mode cpu))))
  (let ((result (rotate-byte (funcall mode cpu) -1)))
    (funcall setf-form result)
    (set-flags-nz cpu result)))

(defopcode rti (:docs "Return from Interrupt")
    ((#x40 6 1 'implied))
  (setf (cpu-sr cpu) (stack-pop cpu))
  (setf (cpu-pc cpu) (stack-pop-word cpu)))

(defopcode rts (:docs "Return from Subroutine" :track-pc nil)
    ((#x60 6 1 'implied))
  (setf (cpu-pc cpu) (1+ (stack-pop-word cpu))))

(defopcode sbc (:docs "Subtract from Accumulator with Carry")
    ((#xe1 6 2 'indirect-x)
     (#xe5 3 2 'zero-page)
     (#xe9 2 2 'immediate)
     (#xed 4 3 'absolute)
     (#xf1 5 2 'indirect-y)
     (#xf5 4 2 'zero-page-x)
     (#xf9 4 3 'absolute-y)
     (#xfd 4 3 'absolute-x))
  ; TODO: This is a naive implementation. Have a look at py6502's opSBC.
  (let ((result (- (cpu-ar cpu) (funcall mode cpu) (status-bit :carry cpu))))
    (setf (cpu-ar cpu) result)
    (update-flags result cpu '(:carry :overflow :negative :zero))))

(defopcode sec (:docs "Set Carry Flag")
    ((#x38 2 1 'implied))
  (setf (status-bit :carry cpu) 1))

(defopcode sed (:docs "Set Decimal Flag")
    ((#xf8 2 1 'implied))
  (setf (status-bit :decimal cpu) 1))

(defopcode sei (:docs "Set Interrupt Flag")
    ((#x78 2 1 'implied))
  (setf (status-bit :interrupt cpu) 1))

(defopcode sta (:docs "Store Accumulator" :raw t)
    ((#x81 6 2 'indirect-x)
     (#x85 3 2 'zero-page)
     (#x8d 4 3 'absolute)
     (#x91 6 2 'indirect-y)
     (#x95 4 2 'zero-page-x)
     (#x99 5 3 'absolute-y)
     (#x9d 5 3 'absolute-x))
  (funcall setf-form (cpu-ar cpu)))

(defopcode stx (:docs "Store X register" :raw t)
    ((#x86 3 2 'zero-page)
     (#x8e 4 3 'absolute)
     (#x96 4 2 'zero-page-y))
  (funcall setf-form (cpu-xr cpu)))

(defopcode sty (:docs "Store Y register" :raw t)
    ((#x84 3 2 'zero-page)
     (#x8c 4 3 'absolute)
     (#x94 4 2 'zero-page-x))
  (funcall setf-form (cpu-yr cpu)))

(defopcode tax (:docs "Transfer Accumulator to X register")
    ((#xaa 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (cpu-ar cpu))))
    (set-flags-nz cpu result)))

(defopcode tay (:docs "Transfer Accumulator to Y register")
    ((#xa8 2 1 'implied))
  (let ((result (setf (cpu-yr cpu) (cpu-ar cpu))))
    (set-flags-nz cpu result)))

(defopcode tsx (:docs "Transfer Stack Pointer to X register")
    ((#xba 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (cpu-sp cpu))))
    (set-flags-nz cpu result)))

(defopcode txa (:docs "Transfer X register to Accumulator")
    ((#x8a 2 1 'implied))
  (let ((result (setf (cpu-ar cpu) (cpu-xr cpu))))
    (set-flags-nz cpu result)))

(defopcode txs (:docs "Transfer X register to Stack Pointer")
    ((#x9a 2 1 ' implied))
  (setf (cpu-sp cpu) (cpu-xr cpu)))

(defopcode tya (:docs "Transfer Y register to Accumulator")
    ((#x98 2 1 'implied))
  (let ((result (setf (cpu-ar cpu) (cpu-yr cpu))))
    (set-flags-nz cpu result)))
