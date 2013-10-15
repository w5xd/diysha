chmod +x HaPrerequisites 
#detach the process running the upgrade from stdin, stdout, stderr.
#The apt-get upgrade run by this script might very well destroy the
#terminal we are running from, depending on exactly who launches it.
./HaPrerequisites < /dev/null > HaPrerequisites.log 2>&1 &
echo "Update and upgrade script is launched"

