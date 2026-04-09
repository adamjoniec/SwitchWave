#!/bin/bash
# Usage: file-in file-out

set -eo pipefail

if ! [ -x "$(command -v gimp)" ]; then
    echo "Error: gimp not found" >&2
    exit 1
fi

INPUT_BASENAME=$(basename "$1" | cut -d '.' -f 1)
if [[ "$INPUT_BASENAME" =~ ^(.+)-([0-9]+)[x\*]([0-9]+)-([^-]+)$ ]]; then
    NAME="${BASH_REMATCH[1]}"
    WIDTH="${BASH_REMATCH[2]}"
    HEIGHT="${BASH_REMATCH[3]}"
    COMP="${BASH_REMATCH[4]}"
else
    echo "Error: invalid texture filename format '$INPUT_BASENAME'" >&2
    exit 1
fi

GIMP_MAJOR=$(gimp --version 2>&1 | grep -oP '\d+' | head -1)
COMP_LOWER="${COMP,,}"

case "$COMP_LOWER" in
  "bc1") METHOD="1" ;;
  "bc2") METHOD="2" ;;
  "bc3") METHOD="3" ;;
  "bc4") METHOD="5" ;;
  "bc5") METHOD="6" ;;
   *) echo "Error: unknown compression format '$COMP'" >&2; exit 1 ;;
esac

if [ "$GIMP_MAJOR" -ge 3 ] 2>/dev/null; then
    # GIMP 3: uses gimp-console with keyword arguments and file-dds-export
    TMPPATH=$(mktemp --suffix=.dds /tmp/"$NAME"_XXXXXXXXX)

    run_gimp3_export() {
        local comp_format="$1"
        gimp-console -n -i -c --batch-interpreter=plug-in-script-fu-eval -b "
        (let* (
                (image (car (file-svg-load
                    #:run-mode RUN-NONINTERACTIVE
                    #:file \"$1\"
                    #:width $WIDTH
                    #:height $HEIGHT
                    #:keep-ratio FALSE
                    #:paths \"no-import\")))
            )
            (file-dds-export
                #:run-mode RUN-NONINTERACTIVE
                #:image image
                #:file \"$TMPPATH\"
                #:options -1
                #:compression-format \"$comp_format\"
                #:perceptual-metric FALSE
                #:format \"default\"
                #:save-type \"canvas\")
            (gimp-image-delete image)
        )" \
        -b "(gimp-quit 0)"
    }

    if ! run_gimp3_export "$COMP_LOWER" && ! run_gimp3_export "${COMP_LOWER^^}"; then
        echo "Error: GIMP failed to convert $1 with compression '$COMP_LOWER'" >&2
        exit 1
    fi

    if [ ! -s "$TMPPATH" ]; then
        echo "Error: GIMP produced no output for $1" >&2
        exit 1
    fi

    dd if="$TMPPATH" of="$2" bs=1 skip=128 2>/dev/null
else
    # GIMP 2: uses gimp with positional arguments and file-dds-save
    gimp -i -b "
        (let* (
                (image (car (file-svg-load RUN-NONINTERACTIVE \"$1\" \"$1\" 90 $WIDTH $HEIGHT 0)))
                (drawable (car (gimp-image-get-active-layer image)))
            )
            (file-dds-save RUN-NONINTERACTIVE image drawable \"/dev/stdout\" \"/dev/stdout\" $METHOD 0 0 0 -1 0 0 0 0 0 0 0 0)
            (gimp-image-delete image)
        )" \
        -b "(gimp-quit 0)" \
        | dd of="$2" bs=1 skip=128 2>/dev/null
fi
