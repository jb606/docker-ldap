docker run --rm -it \
	-p "389:389" \
	-p "636:636" \
	-v "$(pwd)/ldif:/files/ldif.d" \
	-v "$(pwd)/certs:/certs" \
	-v "$(pwd)/data:/data"\
	--env-file .env\
	--entrypoint /data/entrypoint.sh \
       	--name LDAPME \
	bollingerjk/ldap:latest
#docker run --rm -it -p "389:389" -p "636:636" --env-file .env -v "$(pwd)/data:/data" --name LDAPME bollingerjk/ldap:latest
#docker run --rm -it -p "389:389" -p "636:636" -v "$(pwd)/certs:/certs" -v "$(pwd)/data:/data" --env-file .env --entrypoint bash --name LDAPME bollingerjk/ldap:latest 
