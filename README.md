# gform2htmlapp
Perl application that converts Google Forms into customizable HTML.

- By default, Bootstrap is used.
- For the time being only single-page forms are supported.
- Question types currently supported: Radio, Checkbox, and plain text.
- Nothing is stored in the database.
- The form must not require Login to the Google account.

## How to run locally
0. Clone this repo and `cd` to the `gform2htmlapp`.
1. Make sure you have Docker installed:
`docker --version`
2. Build the Docker image
`docker build -t gform2htmlapp .`
3. Run the container locally:
`docker run -p 8080:8080 gform2htmlapp`
