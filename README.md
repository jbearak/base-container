# Base Container

A comprehensive, reproducible development environment using VS Code dev containers. Includes essential tools for data science, development, and document preparation.

## Features
- **Development Tools**: Git, R, Python, shell utilities
- **R Packages**: Comprehensive set for data analysis and modeling  
- **Document Preparation**: LaTeX, Pandoc for typesetting

## Quick Setup

**Prerequisites**: [VS Code](https://code.visualstudio.com/) with [Remote Development](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack) extension

### macOS: Install and Configure Colima

If you're on macOS, you'll need to install and properly configure Colima for correct file permissions:

1. **Install Colima with Homebrew:**
   ```bash
   brew install colima
   ```

2. **Start Colima as a service (persists across reboots):**
   ```bash
   brew services start colima
   ```

3. **Important: Reconfigure for proper UID/GID mapping**
   
   The initial installation uses SSHFS, which causes permission errors when accessing project files from within the container. You need to reconfigure Colima to use the `vz` virtualization framework:
   
   ```bash
   colima stop
   colima delete
   colima start --vm-type vz --mount-type virtiofs
   ```
   
   Once configured this way, Colima will remember these settings and use `vz` for future starts.

### Container Setup

1. **Create `.devcontainer/devcontainer.json` in your project:**

```jsonc
{
  "name": "Base Container Development Environment",
  "image": "ghcr.io/jbearak/base-container:latest",

  // For Colima on macOS, use vz for correct UID/GID mapping:
  // colima stop; colima delete; colima start --vm-type vz --mount-type virtiofs

  // Use non-root user "me". Set to "root" if needed.
  "remoteUser": "me",
  "updateRemoteUserUID": true,

  // Mount local Git config for container Git usage
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,consistency=cached,readonly"
  ],

  // Set container timezone from host
  "containerEnv": {
    "TZ": "${localEnv:TZ}"
  }
}
```

2. **Open in VS Code:**
   - Open your project folder in VS Code
   - When prompted, click "Reopen in Container"

The container will automatically download and start your development environment.

## Amazon Q CLI Integration

For projects that use Amazon Q CLI, you can extend the base container with Amazon Q installation and configuration. Here's an example devcontainer.json that includes Amazon Q CLI for Linux ARM:

```jsonc
{
  "name": "Base Container with Amazon Q CLI",
  "image": "ghcr.io/jbearak/base-container:latest",

  // Use non-root user "me". Set to "root" if needed.
  "remoteUser": "me",
  "updateRemoteUserUID": true,

  // Mount local Git config and AWS/Q configurations
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,consistency=cached,readonly",
    // --- AWS/Q Configuration ---
    // This mounts your AWS configuration directory to persist Q login information
    "source=${localEnv:HOME}/.aws,target=/home/me/.aws,type=bind,consistency=cached",
    // --- Amazon Q Local Data ---
    // This mounts the Amazon Q local data directory to persist authentication state
    "source=${localEnv:HOME}/.local/share/amazon-q,target=/home/me/.local/share/amazon-q,type=bind,consistency=cached"
    // Note: The container will fail to start if these directories do not exist on the host.
    // You can create them with `mkdir -p ~/.aws` and `mkdir -p ~/.local/share/amazon-q`
  ],

  // Set container timezone from host
  "containerEnv": {
    "TZ": "${localEnv:TZ}"
  },

  // Install Amazon Q CLI on container creation
  "postCreateCommand": "curl -sSL https://aws-cli-q-installer.s3.amazonaws.com/q-installer-linux-arm64.tar.gz | tar -xz && sudo ./q-installer-linux-arm64/install && rm -rf ./q-installer-linux-arm64"
}
```

**Important Setup Notes:**
- Create the required directories on your host before starting the container:
  ```bash
  mkdir -p ~/.aws ~/.local/share/amazon-q
  ```
- After the container starts, authenticate with Amazon Q:
  ```bash
  q auth
  ```

## License

Licensed under the [MIT License](LICENSE.txt).
