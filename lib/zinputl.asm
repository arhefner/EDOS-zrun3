#include    include/opcodes.def
#include    include/kernel_api.inc

            proc    z_inputl
            ghi     re                  ; disable echo
            stxd
            ani     0feh
            phi     re

            glo     rb
            stxd
            ghi     rb
            stxd

            ldi     0
            plo     rb
            phi     rb

inloop:     call    K_READ
            plo     re
			
            smi     127
            lbdf    inloop

            adi     127-32
            lbdf    print

            adi     32-21
            lbz     bs

            adi     21-13
            lbz     cr

            adi     13-8
            lbz     bs

            adi     8-3
            lbnz    inloop

            ldi     1
            lbr     endin

cr:         glo     re
            call    K_TYPE

            ldi     0

endin:      shr
            str     rf

            irx
            ldxa
            phi     rb
            ldxa
            plo     rb

            ldx
            phi     re
            
            rtn

print:      glo     rc
            lbnz    save
            ghi     rc
            lbz     inloop

save:       glo     re
            str     rf

            inc     rf
            inc     rb
            dec     rc

            call    K_TYPE
            lbr     inloop

bs:         glo     rb
            lbnz    back
            ghi     rb
            lbz     inloop

back:       dec     rf
            dec     rb
            inc     rc

            glo     re
            stxd

            call    K_INMSG
            db      8,32,8,0

            irx
            ldx
            plo     re

            smi     21
            lbz     bs

            lbr     inloop
			
			endp
