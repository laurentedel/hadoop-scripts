#!/usr/bin/awk -f

BEGIN {
        if (!THRESHOLD) {
                print "Undefined THRESHOLD parameter, please fixe this" > "/dev/stderr"
                exit 1
        }
        f1=""
        trigger=0
}
/^.*/ {
        if ($3 < THRESHOLD) {
                if (trigger) {
                        printf("merge_region '%s','%s'\n", f1, $1)
                        printf("sleep 60\n")
                        trigger = 0
                        next
                } else trigger = 0
                trigger = 1
                f1 = $1
        } else trigger = 0
}
