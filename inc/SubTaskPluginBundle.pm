use strict;
use warnings;
package # stay away, PAUSE!
    inc::SubTaskPluginBundle;
# ABSTRACT: A plugin bundle for building Task::Kensho:: subdists
# vim: set ts=8 sts=4 sw=4 tw=115 et :

use 5.014;  # s///r
use Moose;
with
    'MooseX::SimpleConfig',
    'Dist::Zilla::Role::PluginBundle::Easy',
    'Dist::Zilla::Role::PluginBundle::PluginRemover' => { -version => '0.103' },
    'Dist::Zilla::Role::PluginBundle::Config::Slicer',
    'Dist::Zilla::Role::BundleDeps';

use Devel::CheckBin 'can_run';
use Config;
use namespace::autoclean;

# this is ripped off wholesale from Dist::Zilla::PluginBundle::Author::ETHER
# 0.068, with customizations removed that we do not want.. and also less
# manipulation of the git repo, and silly irrelevant tests removed.

has distname => (
    is => 'ro', isa => 'Str',
    lazy => 1,
    default => sub { shift->payload->{distname} // die 'missing required option: \'distname\'' ; },
);

has configfile => (
    is => 'ro', isa => 'Str',
    lazy => 1,
    default => sub { shift->payload->{configfile} // '../modules.yml'; },
);

has _module_data => (
    isa => 'HashRef[HashRef[Str|HashRef[Str]]]',
    traits => ['Hash'],
    handles => { data_for => 'get' },
    lazy => 1,
    default => sub {
        my $self = shift;
        $self->get_config_from_file($self->configfile);
    },
);

my $has_bash = can_run('bash');

sub configure
{
    my $self = shift;

    my $module = $self->distname =~ s/-/::/gr;
    my $module_data = $self->data_for($module);

    my @plugins = (
        # no VersionProvider: it is hardcoded in dist.ini

        # Gather Files
        [ 'Git::GatherDir'      => { ':version' => '2.016', exclude_match => '^inc', exclude_filename => [ 'dist.ini', 'modules.yml', 'META.json', 'README.md', 'README.pod' ] } ],
        [ 'MungeFile::WithConfigFile' => { finder => ':InstallModules', files => ['README'], configfile => $self->configfile } ],
        qw(MetaYAML MetaJSON Manifest),
        [ 'License'             => { ':version' => '5.038', filename => 'LICENCE' } ],
        [ 'Test::Compile'       => { ':version' => '2.039', bail_out_on_fail => 1, xt_mode => 1 } ],
        'Test::NoTabs',
        'Test::EOL',
        'MetaTests',
        [ 'Test::CPAN::Changes' => { ':version' => '0.012' } ],
        'Test::ChangesHasContent',
        [ 'Test::MinimumVersion' => { ':version' => '2.000008', max_target_perl => '5.006' } ],
        [ 'PodSyntaxTests'      => { ':version' => '5.040' } ],
        [ 'PodCoverageTests'    => { ':version' => '5.040' } ],
        [ 'Test::PodSpelling'   => { ':version' => '2.006003', stopwords => ['irc'] } ],
        # 'Test::Pod::No404s',  # TODO: see RT#105937
        [ 'Test::Kwalitee'      => { ':version' => '2.10', filename => 'xt/author/kwalitee.t' } ],
        [ 'MojibakeTests'       => { ':version' => '0.8' } ],
        [ 'Test::ReportPrereqs' => {    # gives us something in t/
                ':version' => '0.022',
                verify_prereqs => 1,
                version_extractor => 'ExtUtils::MakeMaker',
            } ],
        [ 'Test::Portability'   => { ':version' => '2.000007' } ],
        [ 'Test::CleanNamespaces' => { ':version' => '0.006' } ],

        # Munge Files
        [ 'Git::Describe'       => { ':version' => '0.004', on_package_line => 1 } ],
        [ PodWeaver             => { ':version' => '4.005', config_plugin => '@Author::ETHER', replacer => 'replace_with_comment', post_code_replacer => 'replace_with_nothing' } ],
        [ 'NextRelease'         => { ':version' => '4.300018', time_zone => 'UTC', format => '%-8v  %{yyyy-MM-dd}d%{ (TRIAL RELEASE)}T' } ],

        # MetaData
        [ 'GithubMeta'          => { issues => 1 } ],
        [ 'Authority'           => { ':version' => '1.009', authority => 'cpan:PERIGRIN', do_munging => 0 } ],
        [ 'MetaNoIndex'         => { directory => [ qw(t xt examples share) ] } ],
        [ 'MetaProvides::Package' => { ':version' => '1.15000002', finder => ':InstallModules', meta_noindex => 1, inherit_version => 0, inherit_missing => 0 } ],
        'MetaConfig',
        # [Git::Contributors]
        # (StaticInstall)
        [ 'MetaResources'       => { x_IRC => 'irc://irc.perl.org/#epo' } ],
        [ 'Keywords'            => { ':version' => '0.004', keywords => [ qw(EPO enlightened recommendations curated) ] } ],
        ($Config{default_inc_excludes_dot} ? [ 'UseUnsafeInc' => { dot_in_INC => 0 } ] : ()),

        # Register Prereqs
        'AutoPrereqs',
        'MinimumPerl',
        [ 'Prereqs' => 'task components' => {
                '-phase' => 'runtime', '-relationship' => 'requires',
                (map +($_ => 0), keys %{ $module_data->{components} }),
            } ],

        # we prefer this to run after other Register Prereqs plugins
        [ 'Git::Contributors'   => { ':version' => '0.029', order_by => 'commits', paths => [ '.', '../modules.yml' ] } ],

        # Test Runner
        [ 'RunExtraTests'       => { ':version' => '0.024' } ],

        # Install Tool
        'MakeMaker',
        [ 'StaticInstall'       => { ':version' => '0.005', mode => 'auto' } ],

        # After Build
        'CheckSelfDependency',

        # Before Release
        [ 'CheckStrictVersion'  => { decimal_only => 1 } ],
        [ 'Git::Check'          => 'initial check' => { repo_root => '..', allow_dirty => [''] } ],
        'Git::CheckFor::MergeConflicts',
        [ 'Git::CheckFor::CorrectBranch' => { ':version' => '0.004', release_branch => 'master' } ],
        [ 'Git::Remote::Check'  => { branch => 'master', remote_branch => 'master' } ],
        [ 'CheckPrereqsIndexed' => { ':version' => '0.019' } ],
        'TestRelease',
        [ 'Git::Check'          => 'after tests' => { repo_root => '..', allow_dirty => [''] } ],
        'CheckIssues',
        # note: no [ConfirmRelease]

        # Releaser
        'UploadToCPAN',
        [ 'ArchiveRelease'      => { directory => '../released-subtasks' } ],

        # After Release
        [ 'Git::Commit'         => 'release snapshot' => { ':version' => '2.020', add_files_in => ['.'], allow_dirty => [ 'Changes' ], commit_msg => '%N-%v%t%n%n%c' } ],
        # note: no [CopyFilesFromRelease], [Git::Tag], [BumpVersionAfterRelease], [NextRelease], [Git::Commit], [Git::Push]

        [ 'Clean' ],
    );

    $self->add_plugins(@plugins);
}

__PACKAGE__->meta->make_immutable;
