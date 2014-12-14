package WriteOff::Schema::ResultSet::Artist;

use strict;
use base 'WriteOff::Schema::ResultSet';
use WriteOff::Award qw/:all/;

sub _award {
	my ($self, $rs, %p) = @_;

	my $type = $rs->first->type;
	my $colname = { fic => 'story_id', art => 'image_id' }->{$type};
	my %meta = (type => $type, event_id => $rs->first->event_id);

	my %artists;
	my %last;
	my @medals = ( GOLD, SILVER, BRONZE );

	my $mxstdv = $rs->get_column('public_stdev')->max;
	my $n = $rs->count - 1;

	for my $item ($rs->rank_order->all) {
		my $aid = $item->artist_id;

		my @awards = (
			$mxstdv && $item->public_stdev == $mxstdv ? (CONFETTI) : (),
			$item->rank == $n ? (SPOON) : (),
		);

		if (!exists $artists{$aid}) {
			if (%last && $last{rank} == $item->rank) {
				push @awards, $last{medal};
				shift @medals;
			} elsif (@medals) {
				push @awards, shift @medals;
				%last = (rank => $item->rank, medal => $awards[-1]);
			} else {
				undef %last;
			}

			$artists{$aid} = [ [ $item, RIBBON ] ];
		}

		for my $award (@awards) {
			push @{ $artists{$aid} }, [ $item, $award ];
		}
	}

	while (my ($aid, $awards) = each %artists) {
		# Shift ribbon off
		if (@$awards != 1) {
			shift @$awards;
		}

		for (@$awards) {
			my ($item, $award) = @$_;
			$self->find($aid)->create_related('artist_awards', { %meta,
				$colname  => $item->id,
				award_id  => $award->id,
			});
		}
	}
}

sub _distr {
	my ($i, $n, $e) = @_;

	# bigger number -> more brutal curve
	$e //= 1.6;

	# simple exponential curve
	return (($n-$i+1)/($n+2))**$e;
}

sub _score {
	my ($self, $rs) = @_;

	my $type = $rs->first->type;
	my $colname = { fic => 'story_id', art => 'image_id' }->{$type};
	my %meta = (type => $type, event_id => $rs->first->event_id);

	# Multiply by 10 because whole numbers are nicer to display than
	# numbers with one decimal place
	my $D = $rs->difficulty * 10;

	my $n = $rs->count - 1;
	my %artists;
	for my $item ($rs->rank_order->all) {
		my $aid = $item->artist_id;

		my $score = $D * _distr(($item->rank + $item->rank_low) / 2, $n);

		if (exists $artists{$aid}) {
			# Additional entries have a small deduction
			$score -= $D * 0.2;
		}
		else {
			$artists{$aid} = 1;
		}

		$artist->create_related('scores', { %meta,
			$colname => $item->id,
			value    => $score,
			orig     => $score,
		});
	}
}

sub deal_awards_and_scores {
	my ($self, $rs) = @_;
	return unless $rs->count;

	$self->_award($rs);
	$self->_score($rs);
}

sub recalculate_scores {
	my $self = shift;

	$self->result_source->schema->storage->dbh_do(sub {
		my ($storage, $dbh) = @_;

		$dbh->do(qq{
			UPDATE
				artists
			SET
				score =
					(SELECT SUM(value)
						FROM scores
						WHERE artist_id=artists.id);
		});
	});
}

sub tallied {
	my $self = shift;
	my $alltime = shift;

	my $rank_rs = $self->search(
		{
			score => { '>' => { -ident => "me.score" } }
		},
		{
			'select' => [ \'COUNT(*) + 1' ],
			'alias' => 'subq',
		}
	);

	return $self->search(undef, {
		'+select' => [ $rank_rs->as_query ],
		'+as' => [ 'rank' ],
		order_by => [
			{ -desc => "score" },
			{ -asc  => 'name'  },
		]
	})->all;
}

1;

__END__

=pod

=head1 NAME

WriteOff::Schema::ResultSet::Artist - Site's artists.

=head1 METHODS

=head2 tally

Tallies scores from either a L<WriteOff::Schema::ResultSet::Story> resultset or
a L<WriteOff::Schema::ResultSet::Image> resultset by the formula `n - 2p + 1`,
where `n` is the number of items in the tally and `p` is the position of the
item.

Items with tied sort rank are given a position equal to the average of their
indices, e.g., if three items are tied for 2nd place, they will each get a score
where `p = avg(1, 2, 3) = 2`. This maintains the system as zero-sum.

=head2 Awards

Positions 1, 2, and 3 get gold, silver, and bronze medals respectively. In the
case of ties, everyone gets the most valuable medal possible (i.e., five items
all tied for 3rd will each get a bronze medal).

The item with the highest standard deviation in the public voting is awarded
confetti for being the 'Most Controversial'.

The item that comes dead last with no tie is awarded a wooden spoon.

All items with no other award are given a participation ribbon. If an artist
appears more than once in a given set, they are only given one ribbon.

=cut
