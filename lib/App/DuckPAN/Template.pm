package App::DuckPAN::Template;
# ABSTRACT: Template to generate one file of an Instant Answer

# An Instant Answer has multiple templates, each of which can be used
# to generate one output file.

use Moo;

use Try::Tiny;
use Text::Xslate;
use Path::Tiny qw(path);
use Carp;

use namespace::clean;

has name => (
	is       => 'ro',
	required => 1,
	doc      => 'Name of the template',
);

has label => (
	is       => 'ro',
	required => 1,
	doc      => 'Label of the template',
);

has input_file => (
	is       => 'ro',
	required => 1,
	doc      => 'Path of the input file for the template',
);

has output_file => (
	is       => 'ro',
	required => 1,
	doc      => 'Path of the output file for the template. ' .
	            'This string is rendered through Text::Xslate to get the final path. ' .
	            'If a CODE reference is provided, then it is used to generate the output ' .
	            'file - it is passed the same arguments as XSlate would receive.',
);

has output_directory => (
	is       => 'ro',
	init_arg => undef,
	lazy     => 1,
	builder  => 1,
	doc      => 'Directory known to contain all of the generated template output files and subdirectories',
);

has _template_dir_top => (
	is	     => 'ro',
	required => 1,
	doc      => 'Top-level directory containing all templates.',
	init_arg => 'template_directory',
);

has allow => (
	is => 'rwp',
	required => 1,
	doc => 'CODE reference that indicates whether a particular ' .
					'Instant Answer is supported by the template.',
	trigger => \&_normalize_allow_to_sub,
);

sub _normalize_allow_to_sub {
	my ($self, $allow) = @_;
	if (ref $allow eq 'CODE') {
		return $allow;
	}
	elsif (ref $allow eq 'ARRAY') {
		$self->_set_allow(sub {
			my $vars = shift;
			return 1 if grep { $_->($vars) } @$allow;
			return 0;
		});
	}
	else {
		croak("Cannot use @{[ref $allow]} as a predicate");
	}
}

sub supports {
	my ($self, $what) = @_;
	return $self->allow->($what);
}

sub _build_output_directory {
	my ($self) = @_;
	my $out_dir = path($self->output_file);

	# Get the directory that is certain to be the closest ancestor of the
	# output file i.e., keep removing directory parts from the right till the
	# path does not contain any Text::Xslate syntax.
	$out_dir = $out_dir->parent while $out_dir =~ /<:/;

	return $out_dir;
}

has _configure => (
	is => 'ro',
	default => sub { sub { {} } },
	init_arg => 'configure',
);

sub configure {
	my ($self, %options) = @_;
	my $additional = $self->_configure->(%options);
	my $separated = $options{ia}->{perl_module} =~ s{::}{/}gr;
	my $base_separated = $separated =~ s{^DDG/[^/]+/}{}r;
	my $vars = {
		ia                     => $options{ia},
		repo                   => $options{app}->repository,
		package_separated      => $separated,
		package_base_separated => $base_separated,
		%$additional,
	};
	$self->generate($options{app}, $vars);
}

sub indent {
	my $prefix = shift;
	$prefix = ' ' x $prefix if $prefix =~ /^\d+$/;
	return sub {
		my $text = shift;
		join "\n", map { "$prefix$_" } split "\n", $text;
	};
}

# Create the output file from the input file
sub generate {
	my ($self, $app, $vars) = @_;

	# Increased verbosity to help while writing templates
	my $tx = Text::Xslate->new(
		path    => $self->_template_dir_top,
		type    => 'text',
		verbose => 2,
		function => {
			indent => \&indent,
		},
	);

	my $input_file = ref $self->input_file eq 'CODE'
		? $self->input_file->($vars)
		: path($tx->render_string($self->input_file, $vars));

	my $output_file = ref $self->output_file eq 'CODE'
		? $self->output_file->($vars)
		: path($tx->render_string($self->output_file, $vars));

	croak("Template output file $output_file already exists") and return if $output_file->exists;

	my $content = $tx->render($input_file, $vars);

	try {
	    path($output_file)->touchpath->spew_utf8($content);
	} catch {
	    croak "Error creating output file '$output_file' from template: $_";
	};

	return $output_file;
}

1;

