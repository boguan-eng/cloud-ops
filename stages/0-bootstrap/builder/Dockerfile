# Builder image for the IaC pipeline (Cloud Build): gcloud CLI + OpenTofu.
# The official OpenTofu image cannot be used directly as a build step image since 1.10,
# so the tofu binary is copied from the -minimal image into the Google Cloud CLI image.
# Tag the pushed image with the OpenTofu version (images in the repo are immutable).
ARG TOFU_VERSION=1.13.1
ARG CLI_VERSION=594.0.0

FROM ghcr.io/opentofu/opentofu:${TOFU_VERSION}-minimal AS tofu

FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:${CLI_VERSION}-slim
COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu
