@echo off
set "JAVA_HOME=C:\Program Files\Android\Android Studio1\jbr"
set "PATH=%JAVA_HOME%\bin;%PATH%"
cd /d "c:\Users\Utilisateur\Pickupoint\mobile"
call flutter build apk --debug -v
