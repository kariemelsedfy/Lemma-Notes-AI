# Cloud Run image for the pilot proxy (ADR-028). Build context is this directory (Tools/pilot-proxy).
FROM swift:6.2 AS build
WORKDIR /src
COPY Package.swift ./
COPY Sources ./Sources
RUN swift build -c release --product pilot-proxy-server --static-swift-stdlib

FROM ubuntu:24.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libcurl4 zlib1g libxml2 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --no-create-home pilot
COPY --from=build /src/.build/release/pilot-proxy-server /usr/local/bin/pilot-proxy-server
USER pilot
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/pilot-proxy-server"]
