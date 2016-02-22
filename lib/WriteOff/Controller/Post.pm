package WriteOff::Controller::Post;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

sub fetch :Chained('/') :PathPart('post') :CaptureArgs(1) :ActionClass('~Fetch') {}

sub permalink :Chained('fetch') :PathPart('') :Args(0) {
	my ( $self, $c ) = @_;

	my $uri = $c->uri_for_action(
		$c->stash->{post}->entry
			? ($c->stash->{post}->entry->view, [ $c->stash->{post}->entry->id_uri ])
			: ('/event/permalink', [ $c->stash->{post}->event->id_uri ])
	);

	$c->res->redirect($uri . "#" . $c->stash->{post}->id);
}

sub add :Local {
	my ($self, $c) = @_;

	return unless $c->user->active_artist_id;
	$c->forward('/check_csrf_token');

	if ($c->req->param('event') =~ /(\d+)/) {
		$c->stash->{event} = $c->model('DB::Event')->find($1);
	}

	$c->detach('/error') unless $c->stash->{event} && $c->stash->{event}->commenting;

	my %post = (
		artist_id => $c->user->active_artist_id,
		event_id => $c->stash->{event}->id,
		body => $c->req->param('body'),
	);

	if ($c->req->param('entry') =~ /(\d+)/) {
		if ($c->stash->{entry} = $c->model('DB::Entry')->find($1)) {
			$c->detach('/error') unless $c->stash->{event}->fic_gallery_opened;
			$post{entry_id} = $c->stash->{entry}->id;
		}
	}

	my $post = $c->model('DB::Post')->new_result(\%post);
	$post->render;
	$post->insert;

	$c->res->redirect($c->uri_for_action('/post/permalink', [ $post->id ]));
}

__PACKAGE__->meta->make_immutable;

1;
