package WriteOff::View::TT;
use utf8;
use 5.014;
use JSON;
use Moose;
use namespace::autoclean;
use Template::Stash;
use Template::Filters;
use Template::AutoFilter::Parser;
use Parse::BBCode;
use Text::Markdown;
use WriteOff::Util;
use WriteOff::DateTime;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
	WRAPPER            => 'wrapper.tt',
	ENCODING           => 'utf-8',
	TEMPLATE_EXTENSION => '.tt',
	START_TAG          => quotemeta('{{'),
	END_TAG            => quotemeta('}}'),
	TIMER              => 1,
	expose_methods     => [ qw/csrf_field format_dt title_html spectrum/ ],
	render_die         => 1,
);

__PACKAGE__->config->{FILTERS} = {
	markdown => sub {
		my $text = shift;
		$text = Text::Markdown->new->markdown($text);
		$text =~ s{</li>}{}g;
		return $text;
	},

	externallinks => sub {
		return shift =~ s{(<a [^>]+ >) ([^<]+) </a>}{$1<i class="fa fa-external-link"></i> $2</a>}rgx;
	},

	bbcode => [sub {
		my $c = shift;
		my $opt = shift // {};

		return sub {
			my $text = shift;
			$text = WriteOff::Util::bbcode($text);

			if ($opt->{xhtml}) {
				$text =~ s{<hr>}{<hr/>}g;
				$text =~ s{<br>}{<br/>}g;
			}

			return $text;
		};
	}, 1],

	simple_uri => \&WriteOff::Util::simple_uri,
	none => sub { $_[0] },
};

__PACKAGE__->config->{PARSER} = Template::AutoFilter::Parser->new(__PACKAGE__->config);

$Template::Stash::SCALAR_OPS = {
	%$Template::Stash::SCALAR_OPS,

	ucfirst => sub {
		return ucfirst shift;
	},
};

$Template::Stash::LIST_OPS = {
	%$Template::Stash::LIST_OPS,

	join_serial => sub {
		my @list = @{+shift};

		return join ", ", @list if $#list < 2;

		my $last = pop @list;
		$list[-1] .= ", and $last";

		return join ", ", @list;
	},

	join_en => sub {
		join " – ", @{$_[0]};
	},

	sort_stdev => sub {
		return [ sort { $b->stdev <=> $a->stdev } @{ $_[0] } ]
	},

	map_username => sub {
		return [ map { $_->username } @{ $_[0] } ];
	},

	json => sub {
		return encode_json $_[0];
	},
};

sub csrf_field {
	my ($self, $c) = @_;

	return sprintf qq{<input type="hidden" name="csrf_token" value="%s">}, $c->csrf_token;
}

sub format_dt {
	my ($self, $c, $dt, $fmt, $tz) = @_;

	return '' unless eval { $dt->set_time_zone('UTC')->isa('DateTime') };

	$tz //= $c->user->timezone || 'UTC';

	return sprintf '<time title="%s" datetime="%sZ">%s</time>',
		$dt->rfc2822,
		$dt->iso8601,
		do {
			my $local = $dt->clone->set_time_zone($tz);
			defined $fmt ? $local->strftime($fmt) : $local->rfc2822;
		};
}

sub spectrum {
	my ($self, $c, $left, $right, $pos) = @_;

	# Assuming RGB triplets;
	my @left = map { hex $_ x 2 } split //, $left;
	my @right = map { hex $_ x 2 } split //, $right;

	my @diff = map { $right[$_] - $left[$_] } 0..2;

	return join '', map {
		sprintf "%02x", int($left[$_] + $diff[$_] * $pos)
	} 0..2;
}

sub title_html {
	my ($self, $c) = @_;
	my $title = $c->stash->{title};
	$title = join " &#8250; ",
	           map { Template::Filters::html_filter($_) }
	             ref $title eq 'ARRAY' ? reverse @$title : $title || ();
	return join " &#x2022; ", $title || (), $c->config->{name};
}

1;
