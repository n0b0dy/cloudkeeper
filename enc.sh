#!/bin/bash

# ./encrypt.sh -keys public.pem private.pem
# ./encrypt.sh folder public.pem > decrypt-folder.sh
# chmod +x decrypt-folder.sh
# ./decrypt-folder.sh private.pem > folder.tar
#
# 
# $ ./encrypt.sh
# Usage: ./encrypt-file.sh [directory] [public-key] > [decryption-script]
# or: ./encrypt-file.sh -keys [public-key] [private-key]
#
compress='bzip2' #bzip2, xz, gz

if [ "x$1" = x-keys ] ; then

    # Сгенерированные ключи не должны быть доступны для чтения
    umask 077

    PUBLICKEY="$2"
    PRIVATEKEY="$3"
    if [ x"$PRIVATEKEY" = x ] ; then
        echo "Usage: $0 [public-key] [private-key]"
        exit 1
    fi

    # Проверка имеющихся ключей
    for f in "$PUBLICKEY" "$PRIVATEKEY" ; do
        if [ -e "$f" ] ; then
            echo -n "Ключ $f уже существует! Перезаписать? (y/n) "
            [ `head -n 1` = 'y' ] || exit 1
        fi
    done

    # Генерация новых ключей
    echo "Введите размер ключа. По-умолчанию 4096"
    read KEYSIZE
    [[ $KEYSIZE == "" ]] && KEYSIZE=4096
    echo "Генерация $KEYSIZE-битного ключа..."
    openssl genrsa -out "$PRIVATEKEY" -aes256 4096
    echo "Создание открытого ключа..."
    openssl rsa -in "$PRIVATEKEY" -pubout -out "$PUBLICKEY"
    echo "Завершено."

    exit
fi

#
# Главный скрипт для упаковки и зашифровки файлов
#
# Смотрите аргументы командной строки
#
ARCHIVEDIR="$1"
PUBLICKEY="$2"

#Подготовка для сжатия
case "$compress" in
    bzip2) compress="bzip2 -zc9"; ext=".tar.bz2";;
       xz) compress="xz -zc9"   ; ext=".tar.xz" ;;
     gzip) compress="gzip -c9"  ; ext=".tar.gz" ;;
        *) compress="cat"        ; ext=".tar"    ;;
esac

if ! [ -e "$ARCHIVEDIR" -a -f "$PUBLICKEY" ] ; then
    echo "Шифрование: $0 [директория] [публичный ключ] > [decryption-script.sh]"
    echo "Генерация ключей: $0 -keys [public.pem] [private.pem]"
    exit 1
fi

# Генерация случайного пароля
PASSIZE=60
export KEY=`openssl rand -base64 $PASSIZE`

# Код, который будет расшифровывать данные, хранящиеся в выходном скрипте
cat <<EOF
#!/bin/sh
PRIVATEKEY="\$1"

if ! [ -f "\$PRIVATEKEY" ] ; then
    echo "Дешифрование: \$0 [private.pem] > [decrypted-archive$ext]"
    exit 1
fi

# Расшифровка с помощью приватного ключа
AESKEY=\` \\
        awk '/^#BKEY/{prn=1;next} /^#EKEY/{exit} prn==1{print}' "\$0" | \\
        openssl enc -base64 -d | \\
    openssl rsautl -decrypt -inkey "\$PRIVATEKEY" \`
export AESKEY

# Использование симметричного для ключа расшифровки данных
awk '/^#BARC/{prn=1;next} /^#EARC/{exit} prn==1{print}' "\$0" | \\
        openssl enc -aes-256-cbc -d -a -pass env:AESKEY

exit

#BKEY
EOF

# Шифрование симметричного ключа с помощью открытого ключа
openssl rsautl -encrypt -inkey "$PUBLICKEY" -pubin <<EOF | openssl enc -base64
$KEY
EOF

echo '#EKEY'
echo '#BARC'

# Создание зашифрованного архива
cd `dirname "$ARCHIVEDIR"`
tar c `basename "$ARCHIVEDIR"` |  eval "$compress" |openssl enc -aes-256-cbc -pass env:KEY -a
echo '#EARC'
