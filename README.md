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
Usage:
  ssh-ca [OPTIONS] COMMAND
  ssh-ca [COMMAND] --help | -h
  ssh-ca --version | -v

Commands:
  install-dependencies   Install dependencies
  initialize             Initialize a new SSH CA key
  clone                  Clone a previously initialized CA key to a new YubiKey
  database               Manage the database
  export                 Export an SSH public key or certificate
  list                   List imported public keys and certificates
  show-certificate       Show an SSH certificate
  sign-host              Sign a host key
  sign-user              Sign a user key
  taildrop               Receive keys over Taildrop and send back signed certificates
  upsert                 Upsert a file in to the database
```

### Signing over Taildrop
`ssh-ca taildrop sign-user` signs a key that a device sends over [Taildrop](https://tailscale.com/kb/1106/taildrop). The device only needs Tailscale. It takes the same signing options as `sign-user`, but the user's public key comes over Taildrop instead of being passed as an argument:

```
ssh-ca taildrop sign-user --peer my-phone -p alice -V +90D ca.pub alice@my-phone
```

1. ssh-ca prints the commands to run on the device: `tailscale file cp ~/.ssh/id_ed25519.pub <ca-host>:` sends the key (or use the share sheet on Android/iOS), and `tailscale file get --wait --conflict=overwrite ~/.ssh/` waits for the certificate. ssh-ca then waits for one file.
1. It shows the received key: its fingerprint and randomart, whether it is already in the database, and the exact certificate that will be issued. Taildrop doesn't report who sent a file, so compare the fingerprint with `ssh-keygen -lf` on the device.
1. Nothing is signed unless you answer `y` to `Sign this key? [y/N]`. Anything else discards the key.
1. The certificate is stored in the database and sent back to `--peer`. Without `--peer`, you pick the device from a list. If sending fails, the certificate is saved in the current directory.

Anything that isn't exactly one OpenSSH public key (several files, a private key, a certificate, ...) is never signed. It's moved to a `taildrop-rejected-<timestamp>` directory, so unrelated files in the Taildrop inbox aren't lost. Taildrop needs root unless you are the Tailscale operator, so ssh-ca falls back to `sudo` when tailscale denies access. Run `sudo tailscale set --operator=$USER` once to avoid that.

## Building
Building requires Ruby 3.3 or newer (needed by bashly 2.x). Install the build dependencies with `bundle install`, then use `bundle exec rake` to build. The default target will build the application and documentation. Optionally run `bundle exec rake install` to install it locally.

### Building Documentation
Currently, documentation is provied by [bashly.dev](https://bashly.dev/advanced/rendering/). All supported formats can be built at once using `bundle exec rake docs:all`.
