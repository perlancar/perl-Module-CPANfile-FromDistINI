package Module::CPANfile::FromDistINI;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Config::IOD;

our %SPEC;

$SPEC{distini_cpanfile} = {
    v => 1.1,
    summary => 'Generate cpanfile from prereqs information in dist.ini',
    args => {
    },
};
sub distini_cpanfile {
    my %args = @_;

    (-f "dist.ini")
        or return [412, "No dist.ini found. ".
                       "Are you in the right dir (dist top-level)? "];

    my $ct = do {
        open my($fh), "<", "dist.ini" or die "Can't open dist.ini: $!";
        local $/;
        binmode $fh, ":utf8";
        ~~<$fh>;
    };

    my $ciod = Config::IOD->new(
        ignore_unknown_directive => 1,
    );

    my $cfg = $ciod->read_string($ct);

    my %mods_from_ini;
    for my $section ($cfg->list_sections) {
        $section =~ m!^(
                          osprereqs \s*/\s* .+ |
                          osprereqs(::\w+)+ |
                          prereqs (?: \s*/\s* (?<prereqs_phase_rel>\w+))? |
                          extras \s*/\s* lint[_-]prereqs \s*/\s* (assume-(?:provided|used))
                      )$!ix or next;
        my ($phase, $rel);
        if (my $pr = $+{prereqs_phase_rel}) {
            if ($pr =~ /^(develop|configure|build|test|runtime|x_\w+)(requires|recommends|suggests|x_\w+)$/i) {
                $phase = ucfirst(lc($1));
                $rel = ucfirst(lc($2));
            } else {
                return [400, "Invalid section '$section' (invalid phase/rel $pr)"];
            }
        } else {
            $phase = "Runtime";
            $rel = "Requires";
        }

        my %params;
        for my $param ($cfg->list_keys($section)) {
            my $v = $cfg->get_value($section, $param);
            if ($param =~ /^-phase$/) {
                $phase = ucfirst(lc($v));
                next;
            } elsif ($param =~ /^-(relationship|type)$/) {
                $rel = ucfirst(lc($v));
                next;
            }
            $params{$param} = $v;
        }
        #$log->tracef("phase=%s, rel=%s", $phase, $rel);

        for my $param (sort keys %params) {
            my $v = $params{$param};
            if (ref($v) eq 'ARRAY') {
                return [412, "Multiple '$param' prereq lines specified in dist.ini"];
            }
            my $dir = $cfg->get_directive_before_key($section, $param);
            my $dir_s = $dir ? join(" ", @$dir) : "";
            log_trace("section=%s, v=%s, param=%s, directive=%s", $section, $param, $v, $dir_s);

            my $mod = $param;
            $mods_from_ini{$phase}{$mod}   = $v unless $section =~ /assume-provided/;
        } # for param
    } # for section
    log_trace("mods_from_ini: %s", \%mods_from_ini);

    my $cpanfile = "";
    if ($mods_from_ini{Runtime}) {
        for my $k (sort keys %{ $mods_from_ini{Runtime} }) {
            my $v = $mods_from_ini{Runtime}{$k};
            $cpanfile .= "requires '$k'" . ($v ? ", '$v'" : "") . ";\n";
        }
        $cpanfile .= "\n";
    }
    for my $phase (sort keys %mods_from_ini) {
        next if $phase eq 'Runtime';
        $cpanfile .= "on ".lc($phase)." => sub {\n";
        for my $k (sort keys %{ $mods_from_ini{$phase} }) {
            my $v = $mods_from_ini{Runtime}{$k};
            $cpanfile .= "    requires '$k'" . ($v ? ", '$v'" : "") . ";\n";
        }
        $cpanfile .= "};\n\n";
    }

    [200, "OK", $cpanfile];
}

1;
#ABSTRACT:

=head1 SYNOPSIS

See the included script L<distini-cpanfile>.

=cut
