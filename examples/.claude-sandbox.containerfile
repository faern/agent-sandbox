# Install Rust via rustup with default toolchain and rust-analyzer.
# Installs to the container user's home dir so cargo/rustc are on PATH.
#
# claude-sandbox container extension files like these have access
# to the USERNAME variable that will be populated with the user
# the container will run as
FROM fedora:latest

# Install Rust as the sandbox user
USER ${USERNAME}
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain stable --component rust-analyzer
ENV PATH="${USER_HOME}/.cargo/bin:${PATH}"

# ... And set up anything else you might need
RUN echo "I'm a potato" > ~/.secret_msg

