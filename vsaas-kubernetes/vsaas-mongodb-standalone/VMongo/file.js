use admin
db.createUser( { user: "root",
                 pwd: "root@central1234",
                 roles: [ { role: "root", db: "admin" },
                          { role: "readAnyDatabase", db: "admin" },
                          "readWrite"] },
               { w: "majority" , wtimeout: 5000 } )
