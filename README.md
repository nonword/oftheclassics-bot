
bundle install

Per https://github.com/louismullie/stanford-core-nlp:

 - CORENLP_PATH=/root/oftheclassics-bot/stanford-corenlp/
 - `cat "export CORENLP_PATH=/root/oftheclassics-bot/stanford-corenlp/" >> .env`

 - Install corenlp:
 ```
   wget http://nlp.stanford.edu/software/stanford-corenlp-full-2016-10-31.zip -O corenlp.zip
   unzip corenlp.zip
   mv stanford-corenlp-full-2016-10-31 $CORENLP_PATH
   rm corenlp.zip
 ```

 - Install tagger:
 ```
   wget http://nlp.stanford.edu/software/stanford-postagger-full-2014-10-26.zip -O tagger.zip
   unzip tagger.zip
   mv stanford-postagger-full-2014-10-26/* $CORENLP_PATH/.
   rm tagger.zip
   mv stanford-corenlp/models/ stanford-corenlp/taggers
 ```

 - Install bridge
 ```
   wget https://github.com/louismullie/stanford-core-nlp/blob/master/bin/bridge.jar?raw=true -O $CORENLP_PATH/bridge.jar
 ```

(from http://jenniferkruse.me/blog/post20150123.html )

create google voice phone number ( https://www.google.com/voice ), which redirects to mobile

log in as bot user
add google voice number to acct (Settings > Mobile)
set up app at apps.twitter.com


== Server Setup

 - Create DigitalOcean droplet (smallest tier fine - i.e. 512Mb, $5/mo)
 - apt-get update
 - apt install gcc
 - apt install make
 - apt install g++
 - apt install ruby-full
 - apt install ruby-bundler
 - apt install openjdk-8-jdk
 - add following to /etc/environment:
   JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
 - source /etc/environment

Create 2G swap space (cause running the parser typically consumes about one whole G of mem):
 - sudo dd if=/dev/zero of=/swapfile bs=1M count=2000
 - sudo chmod 600 /swapfile
 - sudo mkswap /swapfile
 - sudo swapon /swapfile
 - Add "/swapfile   none    swap    sw    0   0" to end of /etc/fstab

