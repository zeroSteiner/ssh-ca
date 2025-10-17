# usage: ssh_print_certificate $certificate_path
ssh_print_certificate() {
    ssh-keygen -Lf "${1}" | tail -n +2 | sed 's/        /    /g'
}
