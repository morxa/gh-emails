#!/bin/bash
#
# Copyright (c) 2007 Andy Parkins
# Copyright (c) 2009 Tim Niemueller (pimped the script for our needs)
#
# An example hook script to mail out commit update information.  This hook
# sends emails listing new revisions to the repository introduced by the
# change being reported.  The rule is that (for branch updates) each commit
# will appear on one email and one email only.
#
# This hook is stored in the contrib/hooks directory.  Your distribution
# will have put this somewhere standard.  You should make this script
# executable then link to it in the repository you would like to use it in.
# For example, on debian the hook is stored in
# /usr/share/doc/git-core/contrib/hooks/post-receive-email:
#
#  chmod a+x post-receive-email
#  cd /path/to/your/repository.git
#  ln -sf /usr/share/doc/git-core/contrib/hooks/post-receive-email hooks/post-receive
#
# This hook script assumes it is enabled on the central repository of a
# project, with all users pushing only to it and not between each other.  It
# will still work if you don't operate in that style, but it would become
# possible for the email to be from someone other than the person doing the
# push.
#
# Config
# ------
# hooks.mailinglist
#   This is the list that all pushes will go to; leave it blank to not send
#   emails for every ref update.
# hooks.announcelist
#   This is the list that all pushes of annotated tags will go to.  Leave it
#   blank to default to the mailinglist field.  The announce emails lists
#   the short log summary of the changes since the last annotated tag.
# hooks.envelopesender
#   If set then the -f option is passed to sendmail to allow the envelope
#   sender address to be set
# hooks.emailprefix
#   All emails have their subjects prefixed with this prefix, or "[SCM]"
#   if emailprefix is unset, to aid filtering
# hooks.showrev
#   The shell command used to format each revision in the email, with
#   "%s" replaced with the commit id.  Defaults to "git rev-list -1
#   --pretty %s", displaying the commit id, author, date and log
#   message.  To list full patches separated by a blank line, you
#   could set this to "git show -C %s; echo".
#
# Notes
# -----
# All emails include the headers "X-Git-Refname", "X-Git-Oldrev",
# "X-Git-Newrev", and "X-Git-Reftype" to enable fine tuned filtering and
# give information for debugging.
#

# ---------------------------- Functions

check_email()
{
	# --- Arguments
	oldrev=$(git rev-parse $1)
	newrev=$(git rev-parse $2)
	refname="$3"

	# --- Interpret
	# 0000->1234 (create)
	# 1234->2345 (update)
	# 2345->0000 (delete)
	if expr "$oldrev" : '0*$' >/dev/null
	then
		change_type="create"
	else
		if expr "$newrev" : '0*$' >/dev/null
		then
			change_type="delete"
		else
			change_type="update"
		fi
	fi

	# --- Get the revision types
	newrev_type=$(git cat-file -t $newrev 2> /dev/null)
	oldrev_type=$(git cat-file -t "$oldrev" 2> /dev/null)
	case "$change_type" in
	create|update)
		rev="$newrev"
		rev_type="$newrev_type"
		;;
	delete)
		rev="$oldrev"
		rev_type="$oldrev_type"
		;;
	esac

	# The revision type tells us what type the commit is, combined with
	# the location of the ref we can decide between
	#  - working branch
	#  - tracking branch
	#  - unannoted tag
	#  - annotated tag
	case "$refname","$rev_type" in
		refs/tags/*,commit)
			# un-annotated tag
			refname_type="tag"
			short_refname=${refname##refs/tags/}
			;;
		refs/tags/*,tag)
			# annotated tag
			refname_type="annotated tag"
			short_refname=${refname##refs/tags/}
			# change recipients
			if [ -n "$announcerecipients" ]; then
				recipients="$announcerecipients"
			fi
			;;
		refs/heads/*,commit)
			# branch
			refname_type="branch"
			short_refname=${refname##refs/heads/}
			;;
		refs/remotes/*,commit)
			# tracking branch
			refname_type="tracking branch"
			short_refname=${refname##refs/remotes/}
			echo >&2 "*** Push-update of tracking branch, $refname"
			echo >&2 "***  - no email generated."
			return 1
			;;
		*)
			# Anything else (is there anything else?)
			echo >&2 "*** Unknown type of update to $refname ($rev_type)"
			echo >&2 "***  - no email generated"
			return 1
			;;
	esac

	# Check if we've got anyone to send to
	if [ -z "$recipients" ]; then
		case "$refname_type" in
			"annotated tag")
				config_name="hooks.announcelist"
				;;
			*)
				config_name="hooks.mailinglist"
				;;
		esac
		echo >&2 "*** $config_name is not set so no email will be sent"
		echo >&2 "*** for $refname update $oldrev->$newrev"
		return 1
	fi

	return 0
}

# Top level email generation function.  This decides what type of update
# this is and calls the appropriate body-generation routine after outputting
# the common header
#
# Note this function doesn't actually generate any email output, that is
# taken care of by the functions it calls:
#  - generate_email_header
#  - generate_create_XXXX_email
#  - generate_update_XXXX_email
#  - generate_delete_XXXX_email
#  - generate_email_footer
#
generate_email()
{
	# --- Arguments
	oldrev=$(git rev-parse $1)
	newrev=$(git rev-parse $2)
	refname="$3"

	# --- Interpret
	# 0000->1234 (create)
	# 1234->2345 (update)
	# 2345->0000 (delete)
	if expr "$oldrev" : '0*$' >/dev/null
	then
		change_type="create"
	else
		if expr "$newrev" : '0*$' >/dev/null
		then
			change_type="delete"
		else
			change_type="update"
		fi
	fi

	# --- Get the revision types
	newrev_type=$(git cat-file -t $newrev 2> /dev/null)
	oldrev_type=$(git cat-file -t "$oldrev" 2> /dev/null)
	case "$change_type" in
	create|update)
		rev="$newrev"
		rev_type="$newrev_type"
		;;
	delete)
		rev="$oldrev"
		rev_type="$oldrev_type"
		;;
	esac

	# The revision type tells us what type the commit is, combined with
	# the location of the ref we can decide between
	#  - working branch
	#  - tracking branch
	#  - unannoted tag
	#  - annotated tag
	case "$refname","$rev_type" in
		refs/tags/*,commit)
			# un-annotated tag
			refname_type="tag"
			short_refname=${refname##refs/tags/}
			;;
		refs/tags/*,tag)
			# annotated tag
			refname_type="annotated tag"
			short_refname=${refname##refs/tags/}
			# change recipients
			if [ -n "$announcerecipients" ]; then
				recipients="$announcerecipients"
			fi
			;;
		refs/heads/*,commit)
			# branch
			refname_type="branch"
			short_refname=${refname##refs/heads/}
			;;
		refs/remotes/*,commit)
			# tracking branch
			refname_type="tracking branch"
			short_refname=${refname##refs/remotes/}
			exit 1
			;;
		*)
			# Anything else (is there anything else?)
			exit 1
			;;
	esac

	# Check if we've got anyone to send to
	if [ -z "$recipients" ]; then
		case "$refname_type" in
			"annotated tag")
				config_name="hooks.announcelist"
				;;
			*)
				config_name="hooks.mailinglist"
				;;
		esac
		exit 1
	fi

	# Email parameters
	# The email subject will contain the best description of the ref
	# that we can build from the parameters
	describe=$(git describe $rev 2>/dev/null)
	if [ -z "$describe" ]; then
		describe=$rev
	fi

	generate_email_header $oldrev $newrev

	# Call the correct body generation function
	fn_name=general
	case "$refname_type" in
	"tracking branch"|branch)
		fn_name=branch
		;;
	"annotated tag")
		fn_name=atag
		;;
	esac
	generate_${change_type}_${fn_name}_email

	generate_email_footer

	exit 0
}

generate_email_header()
{
	oldrev=$1
	newrev=$2

        case "$change_type" in
        create)
		log_newrev=$newrev
                log_oldrev=$newrev^
                ;;
        delete)
                log_newrev=$oldrev
                log_oldrev=$oldrev^
                ;;
	update)
		log_newrev=$newrev
		log_oldrev=$oldrev
		;;
        esac

	case "$refname_type" in
	tag|"annotated tag")
		subject="Subject: ${emailprefix}$refname_type/$short_refname: $refname_type $short_refname ${change_type}d"
		;;
	*)
		case "$change_type" in
		create)
			subject="Subject: ${emailprefix}$refname_type/$short_refname: created ($describe)"
			;;
		update)
			num_revs=$(git rev-list $log_oldrev..$log_newrev | wc -l)
			if (( $num_revs > 1 )); then
				subject="Subject: ${emailprefix}$refname_type/$short_refname: $num_revs revs ${change_type}d. ($describe)"
			else
				subject="Subject: ${emailprefix}$refname_type/$short_refname: $(git log $log_oldrev..$newrev --pretty=format:'%s')"
			fi
			;;
		delete)
			subject="Subject: ${emailprefix}$refname_type/$short_refname: deleted ($describe)"
			;;
		esac
		;;
	esac

	#Subject: ${emailprefix}$projectdesc $refname_type, $short_refname, ${change_type}d. $describe
	# --- Email (all stdout will be the email)
	# Generate header
	cat <<-EOF
	To: $recipients
	From: $envelope_name <$envelope_email>
	$subject
	X-Git-Refname: $refname
	X-Git-Reftype: $refname_type
	X-Git-Oldrev: $oldrev
	X-Git-Newrev: $newrev
	X-Gitosis-User: $GITOSIS_USER

	Changes have been pushed for the repository "${REPO_DIR##*/}".
	EOF

	echo

	if [ -n "$clone_url" ]; then
		echo "Clone:  $clone_url"
	fi
	if [ -n "$gitweb_url" ]; then
		echo "Gitweb: $gitweb_url"
	fi
	if [ -n "$trac_url" ]; then
		echo "Trac:   $trac_url"
	fi

	echo -e "\nThe $refname_type, $short_refname has been ${change_type}d"
}

generate_email_footer()
{
	SPACE=" "
	cat <<-EOF

	--${SPACE}
	Fawkes Robotics Framework                 http://www.fawkesrobotics.org
	EOF
}

# --------------- Branches

#
# Called for the creation of a branch
#
generate_create_branch_email()
{
	# This is a new branch and so oldrev is not valid
	echo "        at  $newrev ($newrev_type)"
	echo ""
	if [ -n "$gitweb_url" ]; then
		echo "$gitweb_url/$short_refname"
		echo ""
	fi

	echo $LOGBEGIN
	show_new_revisions
	echo $LOGEND

	# Branch update; show revisions not part of $oldrev.
	revspec=$newrev

	if [ "$refname" != refs/heads/trunk ]; then
		other_branches=$(git for-each-ref --format='%(refname)' refs/heads/ |
		    grep -F -v $refname)
	fi

	first_rev=$(git rev-parse --not $other_branches | git rev-list --stdin $revspec | tail -1)
	last_rev=$(git rev-parse --not $other_branches | git rev-list --stdin $revspec | head -1)

	echo ""
	echo $SUMMARY_BEGIN
	git diff-tree --stat --summary --find-copies-harder $first_rev..$last_rev


	# Show diff of changes (for easy review)
	echo
	echo
	echo $DIFF_BEGIN
	echo

	git rev-parse --not $other_branches | git rev-list --reverse --stdin $revspec |
	while read onerev
	do
		git show -C --find-copies-harder --pretty=format:"- *commit* %H - - - - - - - - - -%nAuthor:  %an <%ae>%nDate:    %ad%nSubject: %s%n" --stat $onerev
		echo
		git show -C --find-copies-harder --pretty="format:_Diff for modified files_:" --diff-filter=MT $onerev
		echo
	done
	echo ""
	echo $SECT_BEGIN
}

#
# Called for the change of a pre-existing branch
#
generate_update_branch_email()
{
	# Consider this:
	#   1 --- 2 --- O --- X --- 3 --- 4 --- N
	#
	# O is $oldrev for $refname
	# N is $newrev for $refname
	# X is a revision pointed to by some other ref, for which we may
	#   assume that an email has already been generated.
	# In this case we want to issue an email containing only revisions
	# 3, 4, and N.  Given (almost) by
	#
	#  git rev-list N ^O --not --all
	#
	# The reason for the "almost", is that the "--not --all" will take
	# precedence over the "N", and effectively will translate to
	#
	#  git rev-list N ^O ^X ^N
	#
	# So, we need to build up the list more carefully.  git rev-parse
	# will generate a list of revs that may be fed into git rev-list.
	# We can get it to make the "--not --all" part and then filter out
	# the "^N" with:
	#
	#  git rev-parse --not --all | grep -v N
	#
	# Then, using the --stdin switch to git rev-list we have effectively
	# manufactured
	#
	#  git rev-list N ^O ^X
	#
	# This leaves a problem when someone else updates the repository
	# while this script is running.  Their new value of the ref we're
	# working on would be included in the "--not --all" output; and as
	# our $newrev would be an ancestor of that commit, it would exclude
	# all of our commits.  What we really want is to exclude the current
	# value of $refname from the --not list, rather than N itself.  So:
	#
	#  git rev-parse --not --all | grep -v $(git rev-parse $refname)
	#
	# Get's us to something pretty safe (apart from the small time
	# between refname being read, and git rev-parse running - for that,
	# I give up)
	#
	#
	# Next problem, consider this:
	#   * --- B --- * --- O ($oldrev)
	#          \
	#           * --- X --- * --- N ($newrev)
	#
	# That is to say, there is no guarantee that oldrev is a strict
	# subset of newrev (it would have required a --force, but that's
	# allowed).  So, we can't simply say rev-list $oldrev..$newrev.
	# Instead we find the common base of the two revs and list from
	# there.
	#
	# As above, we need to take into account the presence of X; if
	# another branch is already in the repository and points at some of
	# the revisions that we are about to output - we don't want them.
	# The solution is as before: git rev-parse output filtered.
	#
	# Finally, tags: 1 --- 2 --- O --- T --- 3 --- 4 --- N
	#
	# Tags pushed into the repository generate nice shortlog emails that
	# summarise the commits between them and the previous tag.  However,
	# those emails don't include the full commit messages that we output
	# for a branch update.  Therefore we still want to output revisions
	# that have been output on a tag email.
	#
	# Luckily, git rev-parse includes just the tool.  Instead of using
	# "--all" we use "--branches"; this has the added benefit that
	# "remotes/" will be ignored as well.

	# List all of the revisions that were removed by this update, in a
	# fast forward update, this list will be empty, because rev-list O
	# ^N is empty.  For a non fast forward, O ^N is the list of removed
	# revisions
	fast_forward=""
	rev=""
	for rev in $(git rev-list $newrev..$oldrev)
	do
		revtype=$(git cat-file -t "$rev")
		echo "  discards  $rev ($revtype)"
	done
	if [ -z "$rev" ]; then
		fast_forward=1
	fi

	# List all the revisions from baserev to newrev in a kind of
	# "table-of-contents"; note this list can include revisions that
	# have already had notification emails and is present to show the
	# full detail of the change from rolling back the old revision to
	# the base revision and then forward to the new revision
	firstrev=1
	for rev in $(git rev-list $oldrev..$newrev)
	do
		revtype=$(git cat-file -t "$rev")
		if [ $firstrev == 1 ]; then
			firstrev=0
			echo "        to  $rev ($revtype)"
		else
			echo "       via  $rev ($revtype)"
		fi
	done

	if [ "$fast_forward" ]; then
		echo "      from  $oldrev ($oldrev_type)"
	else
		#  1. Existing revisions were removed.  In this case newrev
		#     is a subset of oldrev - this is the reverse of a
		#     fast-forward, a rewind
		#  2. New revisions were added on top of an old revision,
		#     this is a rewind and addition.

		# (1) certainly happened, (2) possibly.  When (2) hasn't
		# happened, we set a flag to indicate that no log printout
		# is required.

		echo ""

		# Find the common ancestor of the old and new revisions and
		# compare it with newrev
		baserev=$(git merge-base $oldrev $newrev)
		rewind_only=""
		if [ "$baserev" = "$newrev" ]; then
			echo "This update discarded existing revisions and left the branch pointing at"
			echo "a previous point in the repository history."
			echo ""
			echo " * -- * -- N ($newrev)"
			echo "            \\"
			echo "             O -- O -- O ($oldrev)"
			echo ""
			echo "The removed revisions are not necessarilly gone - if another reference"
			echo "still refers to them they will stay in the repository."
			rewind_only=1
		else
			echo "This update added new revisions after undoing existing revisions.  That is"
			echo "to say, the old revision is not a strict subset of the new revision.  This"
			echo "situation occurs when you --force push a change and generate a repository"
			echo "containing something like this:"
			echo ""
			echo " * -- * -- B -- O -- O -- O ($oldrev)"
			echo "            \\"
			echo "             N -- N -- N ($newrev)"
			echo ""
			echo "When this happens we assume that you've already had alert emails for all"
			echo "of the O revisions, and so we here report only the revisions in the N"
			echo "branch from the common base, B."
		fi
	fi

	echo ""
	if [ -n "$gitweb_url" ]; then
		echo "$gitweb_url/$short_refname"
		echo ""
	fi

	if [ -z "$rewind_only" ]; then
		echo "Those revisions listed above that are new to this repository have"
		echo "not appeared on any other notification email; so we list those"
		echo "revisions in full, below."

		echo ""
		echo $LOGBEGIN
		show_new_revisions

		# XXX: Need a way of detecting whether git rev-list actually
		# outputted anything, so that we can issue a "no new
		# revisions added by this update" message

		echo $LOGEND
	else
		echo "No new revisions were added by this update."
	fi

	# The diffstat is shown from the old revision to the new revision.
	# This is to show the truth of what happened in this change.
	# There's no point showing the stat from the base to the new
	# revision because the base is effectively a random revision at this
	# point - the user will be interested in what this revision changed
	# - including the undoing of previous revisions in the case of
	# non-fast forward updates.
	echo ""
	echo $SUMMARY_BEGIN
	git diff-tree --stat --summary --find-copies-harder $oldrev..$newrev

	# Show diff of changes (for easy review)
	echo
	echo
	echo $DIFF_BEGIN
	echo

	# Branch update; show revisions not part of $oldrev.
	revspec=$oldrev..$newrev

	if [ "$refname" != refs/heads/trunk ]; then
		other_branches=$(git for-each-ref --format='%(refname)' refs/heads/ |
		    grep -F -v $refname)
	fi

	git rev-parse --not $other_branches | git rev-list --reverse --stdin $revspec |
	while read onerev
	do
		git show -C --find-copies-harder --pretty=format:"- *commit* %H - - - - - - - - - -%nAuthor:  %an <%ae>%nDate:    %ad%nSubject: %s%n" --stat $onerev
		echo
		git show -C --find-copies-harder --pretty="format:_Diff for modified files_:" --diff-filter=MT $onerev
		echo
	done
	#git diff --no-color $oldrev..$newrev
	echo ""
	echo $SECT_BEGIN
}

#
# Called for the deletion of a branch
#
generate_delete_branch_email()
{
	echo "       was  $oldrev"
	echo ""
	echo $LOGEND
	git show -s --pretty=oneline $oldrev
	echo $LOGEND
}

# --------------- Annotated tags

#
# Called for the creation of an annotated tag
#
generate_create_atag_email()
{
	echo "        at  $newrev ($newrev_type)"

	generate_atag_email
}

#
# Called for the update of an annotated tag (this is probably a rare event
# and may not even be allowed)
#
generate_update_atag_email()
{
	echo "        to  $newrev ($newrev_type)"
	echo "      from  $oldrev (which is now obsolete)"

	generate_atag_email
}

#
# Called when an annotated tag is created or changed
#
generate_atag_email()
{
	# Use git for-each-ref to pull out the individual fields from the
	# tag
	eval $(git for-each-ref --shell --format='
	tagobject=%(*objectname)
	tagtype=%(*objecttype)
	tagger=%(taggername)
	tagged=%(taggerdate)' $refname
	)

	echo "   tagging  $tagobject ($tagtype)"
	case "$tagtype" in
	commit)

		# If the tagged object is a commit, then we assume this is a
		# release, and so we calculate which tag this tag is
		# replacing
		prevtag=$(git describe --abbrev=0 $newrev^ 2>/dev/null)

		if [ -n "$prevtag" ]; then
			echo "  replaces  $prevtag"
		fi
		;;
	*)
		echo "    length  $(git cat-file -s $tagobject) bytes"
		;;
	esac
	echo " tagged by  $tagger"
	echo "        on  $tagged"

	echo ""
	echo $LOGBEGIN

	# Show the content of the tag message; this might contain a change
	# log or release notes so is worth displaying.
	git cat-file tag $newrev | sed -e '1,/^$/d'

	echo ""
	case "$tagtype" in
	commit)
		# Only commit tags make sense to have rev-list operations
		# performed on them
		if [ -n "$prevtag" ]; then
			# Show changes since the previous release
			git rev-list --pretty=short "$prevtag..$newrev" | git shortlog
		else
			# No previous tag, show all the changes since time
			# began
			git rev-list --pretty=short $newrev | git shortlog
		fi
		;;
	*)
		# XXX: Is there anything useful we can do for non-commit
		# objects?
		;;
	esac

	echo $LOGEND
}

#
# Called for the deletion of an annotated tag
#
generate_delete_atag_email()
{
	echo "       was  $oldrev"
	echo ""
	echo $LOGEND
	git show -s --pretty=oneline $oldrev
	echo $LOGEND
}

# --------------- General references

#
# Called when any other type of reference is created (most likely a
# non-annotated tag)
#
generate_create_general_email()
{
	echo "        at  $newrev ($newrev_type)"

	generate_general_email
}

#
# Called when any other type of reference is updated (most likely a
# non-annotated tag)
#
generate_update_general_email()
{
	echo "        to  $newrev ($newrev_type)"
	echo "      from  $oldrev"

	generate_general_email
}

#
# Called for creation or update of any other type of reference
#
generate_general_email()
{
	# Unannotated tags are more about marking a point than releasing a
	# version; therefore we don't do the shortlog summary that we do for
	# annotated tags above - we simply show that the point has been
	# marked, and print the log message for the marked point for
	# reference purposes
	#
	# Note this section also catches any other reference type (although
	# there aren't any) and deals with them in the same way.

	echo ""
	if [ "$newrev_type" = "commit" ]; then
		echo $LOGBEGIN
		git show --no-color --root -s --pretty=medium $newrev
		echo $LOGEND
	else
		# What can we do here?  The tag marks an object that is not
		# a commit, so there is no log for us to display.  It's
		# probably not wise to output git cat-file as it could be a
		# binary blob.  We'll just say how big it is
		echo "$newrev is a $newrev_type, and is $(git cat-file -s $newrev) bytes long."
	fi
}

#
# Called for the deletion of any other type of reference
#
generate_delete_general_email()
{
	echo "       was  $oldrev"
	echo ""
	echo $LOGEND
	git show -s --pretty=oneline $oldrev
	echo $LOGEND
}


# --------------- Miscellaneous utilities

#
# Show new revisions as the user would like to see them in the email.
#
show_new_revisions()
{
	# This shows all log entries that are not already covered by
	# another ref - i.e. commits that are now accessible from this
	# ref that were previously not accessible
	# (see generate_update_branch_email for the explanation of this
	# command)

	# Revision range passed to rev-list differs for new vs. updated
	# branches.
	if [ "$change_type" = create ]
	then
		# Show all revisions exclusive to this (new) branch.
		revspec=$newrev
	else
		# Branch update; show revisions not part of $oldrev.
		revspec=$oldrev..$newrev
	fi

	#always_branches=refs/heads/trunk
	if [ "$refname" != refs/heads/trunk ]; then
		other_branches=$(git for-each-ref --format='%(refname)' refs/heads/ |
		    grep -F -v $refname)
	fi
	#else
	#	other_branches=$(git for-each-ref --format='%(refname)' refs/heads/ |
	#	    grep -F -v $refname | grep -ve $always_branches)
	#fi
	#echo other_branches: $other_branches
	git rev-parse --not $other_branches |
	if [ -z "$custom_showrev" ]
	then
		#git rev-list --pretty=fuller --stdin $revspec
		git rev-list --stdin --reverse $revspec |
		while read onerev
		do
			git log --pretty=fuller -n1 $onerev
			shortrev=$(git log --pretty=format:%h -n1 $onerev)
			echo
			if [ -n "$gitweb_url" ]; then
				for s in $shortrev; do
					echo "$gitweb_url/commit/$s"
				done
			fi
			if [ -n "$trac_url" ]; then
				for s in $shortrev; do
					echo "$trac_url/changeset/$s"
				done
			fi
			echo
			echo $SECTSEP
		done
	else
		git rev-list --stdin --reverse $revspec |
		while read onerev
		do
			shortrev=$(git log --pretty=format:%h -n1 $onerev)
			eval $(printf "$custom_showrev" $onerev)
			echo
			if [ -n "$gitweb_url" ]; then
				for s in $shortrev; do
					echo "$gitweb_url/commit/$s"
				done
			fi
			if [ -n "$trac_url" ]; then
				for s in $shortrev; do
					echo "$trac_url/changeset/$s"
				done
			fi
			echo
			echo $SECTSEP
		done
	fi
}


send_mail()
{
	envelope_email=$1
	envelope_name=$2

	if [ -n "$envelope_email" ]; then
		/usr/sbin/sendmail -t -f "$envelope_email" -F "$envelope_name"
	else
		/usr/sbin/sendmail -t
	fi
}


determine_sender()
{
	if [ -n "$GITOSIS_USER" ]; then
		OIFS=$IFS
		IFS=$'\n'
		for l in $(sed -e 's/^\([^;#][^=]\+\) = \([^<]\+\) <\([^>]\+\)>/\1:\2:\3/' $authors_file); do
        		OIFSF=$IFS
        		IFS=:
        		declare -a AUTHOR=($l)
        		IFS=$OIFSF
			if [ "${AUTHOR[0]}" = "$GITOSIS_USER" ] || [[ "${AUTHOR[0]}" = ".$GITOSIS_USER" ]]; then
				envelope_name=${AUTHOR[1]}
				envelope_email=${AUTHOR[2]}
			fi
		done
		IFS=$OIFS
	fi
}

# ---------------------------- main()

# --- Constants
#LOGEND="-----------------------------------------------------------------------"
LOGBEGIN="- *Log* ---------------------------------------------------------------"
SUMMARY_BEGIN="- *Summary* -----------------------------------------------------------"
DIFF_BEGIN="- *Diffs* -------------------------------------------------------------"
SECTEND="-----------------------------------------------------------------------"
SECTSEP="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# --- Config
if [ -z "$REPO_CONFIG_DIR" ]; then
  echo >&2 "fatal: REPO_CONFIG_DIR not set"
  exit 1
fi
if [ -z "$REPO_DIR" ]; then
	echo >&2 "fatal: post-receive: REPO_DIR not set"
	exit 1
fi

REPO_NAME=$4

# defaults
recipients="hofmann@kbsg.rwth-aachen.de"
announcerecipients=""
emailprefix="[SCM] "
custom_showrev=""
authors_file=AUTHORS
gitweb_url="https://github.com/$REPO_NAME"
tree_url="$gitweb_url/tree"
trac_url="https://github.com/$REPO_NAME/issues"
clone_url="https://github.com/$REPO_NAME.git"

if [ -f $REPO_CONFIG_DIR/$REPO_NAME/config ] ; then
  . $REPO_CONFIG_DIR/$REPO_NAME/config
fi

if [ -z "$envelope_email" ]; then
	envelope_email="noreply@fawkesrobotics.org"
fi
if [ -z "$envelope_name" ]; then
	envelope_name="Fawkes SCM"
fi
if [ -z "$clone_url" ]; then
	clone_url="git@git.fawkesrobotics.org:${REPO_DIR##*/}"
fi

# Set up local repo copy

if [ ! -d $REPO_DIR ] ; then
  mkdir -p $REPO_DIR
  pushd $REPO_DIR
  git clone --bare $clone_url .
  popd
fi

pushd $REPO_DIR
git fetch --tags

# Check if we can determine a sender from the push user setting
determine_sender

# --- Main loop
# Allow dual mode: run from the command line just like the update hook, or
# if no arguments are given then run as a hook script
if [ -n "$1" -a -n "$2" -a -n "$3" ]; then
	generate_email $2 $3 $1 | send_mail "$envelope_mail" "$envelope_name"
else
	while read oldrev newrev refname
	do
		if check_email $oldrev $newrev $refname; then
			generate_email $oldrev $newrev $refname | send_mail "$envelope_email" "$envelope_name"
		fi
	done
fi

popd
