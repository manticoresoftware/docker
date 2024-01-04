# CLT Tests

## Directory Structure

* **testkit** - Contains an image with Bash and Docker in Docker (DinD).
* **tests** - Contains Continuous Integration Tests (CLT).

## Test Procedure

To ensure the robustness of our Docker commands within the image, we generate the latest image from the development branch located in the `base/init` block. This image is tagged as `manticoresoftware/manticore:current`. If you intend to run our image, please use a command similar to the one provided below:
```bash
docker run -e EXTRA=1 --name manticore --rm -d manticoresearch/manticore:current
```
This command will help you launch and manage the Manticore image with the necessary environment variables.

## Run test example

```bash
docker build -t manticoresoftware/manticore-docker-test-kit:latest ./clt_tests/testkit/
RUN_ARGS="-v $(pwd):/docker --privileged" clt test -d -t ./clt_tests/tests/simple.rec manticoresoftware/manticore-docker-test-kit:latest
```
