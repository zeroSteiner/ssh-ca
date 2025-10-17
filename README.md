# SSH CA
This is an implementation of an SSH CA with additional logic to enable storage of the CA key in PIV compatible smart cards such as YubiKeys. This work was originally published at [BSides Cleveland 2025](https://docs.google.com/presentation/d/15iSv4DiH2hChzUvoXQjF-OY86XwEQqy_f9ixQPcuyik/edit?usp=sharing).

## Getting Started
1. Setup [PostgreSQL](https://www.postgresql.org/) for the database.
    1. Create a database and associated user.
1. *Recommended:* Complete the remaining steps from a live-booted OS from a known and trusted distribution such as [Fedora.](https://fedoraproject.org/)
1. *Recommended:* Export the PostgreSQL connection string as a URL in the `SSH_CA_DATABASE_URI` environment variable. For example: `export SSH_CA_DATABASE_URI="postgresql://sshkeys:development@localhost:5432/sshkeys"`
1. Install the latest release and all dependencies
    1. Go to [Releases](https://github.com/zeroSteiner/ssh-ca/releases) and download the latest version.
    1. Mark the binary as executable.
    1. Install the dependencies either manually or using the `ssh-ca install-dependencies` command.
        * The `install-dependencies` command only supports Fedora at this time.
1. Create a new `age` identity in a free slot on each YubiKey by running `age-plugin-yubikey`.
1. Initialize a new CA certificate using the `ssh-ca initialize` command. It's recommended to set KEY-TYPE to RSA3072.
1. Install the SSH CA public key on the target OpenSSH servers. See [How to configure SSH Certificate-Based Authentication](https://goteleport.com/blog/how-to-configure-ssh-certificate-based-authentication/).
1. Sign user and host keys as desired using the `ssh-ca sign-user` and `ssh-ca sign-host` commands respectively.

### Usage
The `ssh-ca` offers a CLI interface.

```
ssh-ca - SSH CA management

Usage:
  ssh-ca [OPTIONS] COMMAND
  ssh-ca [COMMAND] --help | -h
  ssh-ca --version | -v

Commands:
  install-dependencies   Install dependencies
  initialize             Initialize a new SSH CA key
  export                 Export an SSH public key or certificate
  list                   List imported public keys and certificates
  show-certificate       Show an SSH certificate
  sign-host              Sign a host key
  sign-user              Sign a user key
  upsert                 Upsert a file in to the database
```

## Building
To build the project, use `rake`. The default target will build the application and documentation. Optionally run `rake install` to install it locally.

### Building Documentation
Currently, documentation is provied by [bashly.dev](https://bashly.dev/advanced/rendering/). All supported formats can be built at once using `rake docs:all`.
