use base "installbasetest";
use strict;
use testapi;

sub run() {
    my $self = shift;

    # precompile regexes
    my $zypper_dup_continue      = qr/^Continue\? \[y/m;
    my $zypper_dup_conflict      = qr/^Choose from above solutions by number[\s\S,]* \[1/m;
    my $zypper_dup_notifications = qr/^View the notifications now\? \[y/m;
    my $zypper_dup_error         = qr/^Abort, retry, ignore\? \[a/m;
    my $zypper_dup_finish        = qr/^There are some running programs that might use files|^ZYPPER-DONE/m;
    my $zypper_packagekit        = qr/^Tell PackageKit to quit\?/m;
    my $zypper_packagekit_again  = qr/^Try again\?/m;
    my $zypper_repo_disabled     = qr/^Repository '[^']+' has been successfully disabled./m;
    my $zypper_installing        = qr/Installing: \S+/;
    my $zypper_dup_fileconflict  = qr/^File conflicts .*^Continue\? \[y/ms;
    my $zypper_retrieving        = qr/Retrieving: \S+/;
    my $zypper_check_conflicts   = qr/Checking for file conflicts: \S+/;

    # before disable we need to have cdrkit installed to get proper iso appid
    script_run "zypper -n in cdrkit-cdrtools-compat";
    # Disable all repos, so we do not need to remove one by one
    # beware PackageKit!
    script_run("zypper modifyrepo --all --disable | tee /dev/$serialdev");
    my $out = wait_serial([$zypper_packagekit, $zypper_repo_disabled], 120);
    while ($out) {
        if ($out =~ $zypper_packagekit || $out =~ $zypper_packagekit_again) {
            send_key 'y';
            send_key 'ret';
        }
        elsif ($out =~ $zypper_repo_disabled) {
            last;
        }
        $out = wait_serial([$zypper_repo_disabled, $zypper_packagekit_again, $zypper_packagekit], 120);
    }
    unless ($out) {
        save_screenshot;
        $self->result('fail');
        return;
    }

    my $defaultrepo;
    if (get_var('SUSEMIRROR')) {
        $defaultrepo = "http://" . get_var("SUSEMIRROR");
    }
    else {
        #SUSEMIRROR not set, zdup from ftp source for online migration
        if (check_var('TEST', "migration_zdup_online_sle12_ga")) {
            my $flavor  = get_var("FLAVOR");
            my $version = get_var("VERSION");
            my $build   = get_var("BUILD");
            my $arch    = get_var("ARCH");
            $defaultrepo = "ftp://openqa.suse.de/SLE-$version-$flavor-$arch-Build$build-Media1";
        }
        else {
            # SUSEMIRROR not set, zdup from attached ISO
            my $build  = get_var("BUILD");
            my $flavor = get_var("FLAVOR");
            script_run "ls -al /dev/disk/by-label";
            script_run "";
            my $isoinfo = "isoinfo -d -i /dev/\$dev | grep \"Application id\" | awk -F \" \" '{print \$3}'";

            script_run "for dev in sr0 sr1 sr2 sr3 sr4 sr5; do
                       label=`$isoinfo`
                       case \$label in
                           *$flavor-*$build*) echo \"\$dev match\"; export dev=\"/dev/\$dev\"; break;;
                           *) continue;;
                       esac
                       done
                       echo \"found dev \$dev with label \$label\"";
            # if that fails, e.g. if volume descriptor too long, just try /dev/sr0
            $defaultrepo = "dvd:/?devices=\${dev:-/dev/sr0}";
        }
    }

    my $nr = 1;
    foreach my $r (split(/\+/, get_var("ZDUPREPOS", $defaultrepo))) {
        assert_script_run("zypper -n addrepo \"$r\" repo$nr");
        $nr++;
    }
    assert_script_run("zypper -n refresh");

    script_run("(zypper dup -l;echo ZYPPER-DONE) | tee /dev/$serialdev");

    $out = wait_serial([$zypper_dup_continue, $zypper_dup_conflict, $zypper_dup_error], 240);
    while ($out) {
        if ($out =~ $zypper_dup_conflict) {
            if (get_var("WORKAROUND_DEPS")) {
                record_soft_failure;
                send_key '1',   1;
                send_key 'ret', 1;
            }
            else {
                $self->result('fail');
                save_screenshot;
                return;
            }
        }
        elsif ($out =~ $zypper_dup_continue) {
            # confirm zypper dup continue
            send_key 'y',   1;
            send_key 'ret', 1;
            last;
        }
        elsif ($out =~ $zypper_dup_error) {
            $self->result('fail');
            save_screenshot;
            return;
        }
        save_screenshot;
        $out = wait_serial([$zypper_dup_continue, $zypper_dup_conflict, $zypper_dup_error], 120);
    }
    unless ($out) {
        $self->result('fail');
        save_screenshot;
        return;
    }

    # wait for zypper dup finish, accept failures in meantime
    $out = wait_serial([$zypper_dup_finish, $zypper_installing, $zypper_dup_notifications, $zypper_dup_error, $zypper_dup_fileconflict, $zypper_check_conflicts, $zypper_retrieving], 240);
    while ($out) {
        if ($out =~ $zypper_dup_notifications) {
            send_key 'n',   1;    # do not show notifications
            send_key 'ret', 1;
        }
        elsif ($out =~ $zypper_dup_error) {
            $self->result('fail');
            save_screenshot;
            return;
        }
        elsif ($out =~ $zypper_dup_finish) {
            last;
        }
        elsif ($out =~ $zypper_retrieving or $out =~ $zypper_check_conflicts) {
            # probably to avoid hitting black screen on video
            send_key 'shift', 1;
            # continue but do not drop zypper_dup_fileconflict check
            next;
        }
        elsif ($out =~ $zypper_dup_fileconflict) {
            #             record_soft_failure;
            #             send_key 'y', 1;
            #             send_key 'ret', 1;
            $self->result('fail');
            save_screenshot;
            return;
        }
        else {
            # probably to avoid hitting black screen on video
            send_key 'shift', 1;
        }
        save_screenshot;
        $out = wait_serial([$zypper_dup_finish, $zypper_installing, $zypper_dup_notifications, $zypper_dup_error], 240);
    }

    assert_screen "zypper-dup-finish", 2;
}

sub test_flags() {
    return {'fatal' => 1, 'important' => 1};
}

1;
# vim: set sw=4 et:
