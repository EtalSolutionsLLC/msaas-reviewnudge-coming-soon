FROM alpine:3.20

RUN apk add --no-cache bash curl jq python3 coreutils openssl ca-certificates

WORKDIR /opt/portmason/credential-runner
COPY bin/pm-credential-runner /usr/local/bin/pm-credential-runner
RUN chmod +x /usr/local/bin/pm-credential-runner

ENTRYPOINT ["pm-credential-runner"]
CMD ["--help"]
