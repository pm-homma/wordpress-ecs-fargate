FROM wordpress:latest
COPY .htaccess /var/www/html/.htaccess
COPY run.sh /run.sh
RUN apt-get update && apt-get install -y wget sudo \
&& wget https://s3.ap-southeast-1.amazonaws.com/amazon-ssm-ap-southeast-1/latest/debian_amd64/amazon-ssm-agent.deb -O /tmp/amazon-ssm-agent.deb \
&& dpkg -i /tmp/amazon-ssm-agent.deb \
&& cp /etc/amazon/ssm/seelog.xml.template /etc/amazon/ssm/seelog.xml
CMD [ "bash", "/run.sh" ]