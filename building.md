# Docker multi-arch builds

### Getting started

We uses `docker buildx` for building our docker packages. To build new image:
1) Check is `buildex` driver was already started, and re-run it in case check was failed:
  ```shell
    if [[ ! $(docker ps | grep manticore_build) ]]; then
      docker buildx create  --name manticore_build --platform linux/amd64,linux/arm64
      docker buildx use manticore_build
      docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    fi
  ```
2) Next run build:
  ```shell
  docker buildx build \
  --build-arg DEV=1 \
  --push \
  --platform linux/arm64,linux/amd64 \
  --tag manticoresearch/manticore:multi-arch-$BUILD_TAG .
  ```

### Under hood
 
We have two arch for builds (`amd` & `arm`)
* `buildx` command passed to Dockerfile additional argument `TARGETPLATFORM`
    which we used for deciding which arch we want to build `linux/arm64` or `linux/amd64`
* For `dev` builds we call `apt install` so switching between architectures happens automatically
* For `release` builds we passed into `build` variables like `DAEMON_URL`. 
    Very important that each of that links has `_ARCH_` placeholder. Like: 
    ```
    https://repo.manticoreseatch.com/tarball_location/manticore_ARCH_.tgz
    ``` 
    This placeholder substitutes to arch during build process.

### Troubleshooting
* If you see `failed to solve: rpc error: code = Unknown desc = failed to solve with frontend dockerfile.v0: failed to load LLB: runtime execution on platform linux/arm64 not supported` run manually step one from getting started manual
* If you encounter `/bin/sh: Invalid ELF image for this architecture error.` Run `multiarch/qemu-user-static` docker image and then build again
