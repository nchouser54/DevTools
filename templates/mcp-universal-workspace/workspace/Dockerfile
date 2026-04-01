FROM codercom/example-universal:ubuntu

COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh && rm /tmp/bootstrap.sh

WORKDIR /home/coder/project
