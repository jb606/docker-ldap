docker run -itd -p "389:389" -p "636:636" -v "$(pwd)/ldif:/files/ldif.d" --name LDAPME bollingerjk/ldap:latest
