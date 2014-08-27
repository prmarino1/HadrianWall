#!/usr/bin/perl -w
# Description: IPSet-Manager is a tool for loading, comparing, updating, and dumping IPSet's from the Linux Kernel.
# The Dump file format is basicly XML output by the ipset command with a few modifications to make it more practical.
# Updates to existing sets are handled by creating a temporary set and swaping the contents so you dont have to reload your iptables rules.
#
# Author: Paul Robert Marino<code@themarino.net>
# Created at: Feb 27 2:59:19 EST 2013
# 
#
# LICENSE: GPLv2 or higher
#
# Copyright (c) 2013 All rights reserved.
#
# This file is part of The HadrianWall Project.
#
# HadrianWall is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# HadrianWall is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with HadrianWall. If not, see <http://www.gnu.org/licenses/>.
#----------------------------------------------------------------------
#
#==========================================================================================
# BEGIN MODULE LOADING BLOCK
#==========================================================================================

use strict;
# Loading the XML Parser uses for simple reloads without interruption;
use XML::Twig;
# Loading command line option parser
use Getopt::Long  qw(:config bundling);

my $VERSION=0.01;

use Data::Dumper;

#==========================================================================================
# END MODULE LOADING BLOCK
#==========================================================================================

#==========================================================================================
# BEGIN SUBROUTINE BLOCK
#==========================================================================================


# This function initially parses the configuration and calls the parse_configuration function to format the data if contains
# It requires 1 parameter which contains the path on the disk to the configuration file
# If the function excuses successfully it will return a hash reference containing the data.
# In the event that the function fails it will warn the user and return nothing
sub check_configuration_file($){
    # The path to the file
    my $file=shift;
    # Defining an error counter as 0 errors
    my $error=0;
    # Predefining a variable in the appropriate scope to be used latter 
    my $twig_root='';
    # Checking if the configuration file exists on the disk and is an actual file
    unless ( -f $file ){
	# Warning the user that the configuration file does not exist
	warn "Could not find configuration file \"$file\"\n";
	# Increasing the error counter
	$error++;
    }
    else{
	# Verifying that the configuration file is readable
	unless ( -r $file ){
	    # Warning the user that the configuration file is not readable
	    warn "Could not read configuration file \"$file\"\n";
	    # Increasing the error counter
	    $error++;
	}
	# skip the rest if an error has been detected
	unless ($error){
	    # Creating a new instance of the XML::Twig class
	    my $twig=XML::Twig->new();
	    # Loading and parsing the XML file
	    $twig->parsefile($file);
	    # Only proceed if there is data in the XML file
	    if (defined $twig){
		# Defining where to begin processing the XML file
		$twig_root=$twig->root;
		# Checking if there are tags within the <XML> </XML> tags
		unless ($twig_root->children_count){
		    # warning the user that there are no entries in the XML file
		    warn "could not parse configuration file \"$file\" does not appear to be valid XML\n";
		    # Increasing the error counter
		    $error++;
		}
	    }
	    else{
		# warning the user that the XML file could not be parsed
		warn "could not parse configuration file \"$file\" does not appear to be valid XML\n";
		# Increasing the error counter
		$error++;
	    }
	}
    }
    # Only proceed if there have been no errors so far
    unless ($error){
	# parsing and reformatting the data for the sets
	my $sets=parse_configuration($twig_root);
	#only return results if the data has been successfully parsed and formatted
	if (defined $sets){
	    # Returning the hash reference with the formatted data
	    return $sets;
	}
    }
}

# This function initially parses a raw XML configuration and calls the parse_configuration function to format the data if contains
# It requires 1 parameter which contains the content of the XML you want it to process.
# If the function executes successfully it will return a hash reference containing the data.
# In the event that the function fails it will warn the user and return nothing
sub check_configuration($){
    # the variable containing the XML code
    my $xml=shift;
    # Predefining a variable in the appropriate scope to be used latter 
    my $twig_root='';
    # Defining an error counter as 0 errors
    my $error=0;
    # Creating a new instance of the XML::Twig class
    my $twig=XML::Twig->new();
    # Loading and parsing the XML file
    $twig->parse($xml);
    # Only proceed if there is data in the XML file
    if (defined $twig){
	# Defining where to begin processing the XML file
	$twig_root=$twig->root;
	# Checking if there are tags within the <XML> </XML> tags
	unless ($twig_root->children_count){
	    #waring the user if it fails
	    warn "WARNING: Could not parse the running configuration it does not appear to have any sets entries\n";
	    # Showing the user the XML that failed to parse
	    warn "$xml\n";
	    # increasing the value of $error
	    $error++;
	}
    }
    else{
	# Warning the user that the XML file could not be parsed
	warn "ERROR: Could not parse the running configuration it does not appear to be valid XML\n";
	# Showing the user the XML that failed to parse correctly
	 warn "$xml\n";
	$error++;
    }
    # Only proceed if there have been no errors so far
    unless ($error){
	# parsing and reformatting the data for the sets
	my $sets=parse_configuration($twig_root);
	 # Only proceed if there have been no errors so far
	if (defined $sets){
	    # Returning the hash reference with the formatted data 
	    return $sets;
	}
    }
}

# This formats the data contained in the XML into a usable format after its been initial parsed.
# This function requires one parameter a reference to the XML::Twig tree root object instance
# Upon success it returns a hash reference containing the configuration information for all of the sets
# This function warns the user then returns nothing on failure.
sub parse_configuration($){
    # Reference to an XML::Twig root instance
    my $twig=shift;
    # An empty place holder for the result hash reference so it gets the proper scope
    my $sets={};
    # Defining an error counter as 0 errors
    my $error=0;
    # Loop through each ipset tag
    for my $branch ($twig->children){
	# Getting the name of the set
	my $name = $branch->{'att'}->{'name'};
	# Making sure the name is defined
	if (defined $sets->{$name}){
	    # Telling the user that the name is not defined
	    warn "ERROR: set \"$name\" is listed twice\n";
	    # Increasing the error counter
	    $error++;
	}
	else{
	    # Defining a key in the hash with the name of the set and a hash reference as the value
	    $sets->{$name}={};
	    # Looping through the sub tags in the set
	    for my $detail ($branch->children){
		# Getting the name of the type of tag
		my $detailname=$detail->local_name;
		# Checking if the tag is a type tag
		if ($detailname=~/type/){
		    # Setting the type key for the set to the type value of the set
		    $sets->{$name}->{'type'}=$detail->text;
		    
		}
		# The header tag requires special treatment
		elsif($detailname=~/header/){
		    # Defining the header key as an empty hash reference
		    $sets->{$name}->{'headerkeys'}={};
		    # defining the header tag as an array reference because hashes don't maintain variable order this is important for creating sets
		    $sets->{$name}->{'header'}=[];
		    # Looping through each of the sub tags of the header tag for the set
		    for my $field ($detail->children){
			# Ignoring fields which are included in an ipset list -o XML that can not be loaded back in
			unless ( $field->local_name eq 'references' or $field->local_name eq 'memsize'){
			    # setting the key and value for the filed
			    $sets->{$name}->{'headerkeys'}->{$field->local_name}= $field->text;
			    # adding the field to the ordered array for creates
			    push(@{$sets->{$name}->{'header'}},$field->local_name,$field->text);
			}
		    }
		}
		# members require slightly different processing
		elsif($detailname eq 'members'){
		    # creating the members key for the set as an empty array reference
		    $sets->{$name}->{'members'} =[];
		    # Looping through each member tag
		    for my $member ($detail->children){
			# Adding the value to the members array reference
			push(@{$sets->{$name}->{'members'}},$member->text);
		    }
		}
	    }
	}
    }
    # Only proceed if there have been no errors so far 
    unless ($error){
	# returning the hash reference with all of the sets upon success
	return $sets;
    }
    
}

# this function checks the options for conflicting parameters
# this function requires one parameter containing
# 1) A hash reference of the options to the application
# thIs function returns nothing if no conflicts are found
# If conflicts are found it returns the number of conflicts detected
sub cli_confilct_check($){
    # a hash reference containing the options
    my $options=shift;
    # defining a placeholder for a hash where all of the conflicts found are stored so the error messages can be deduplicated
    my $conflicts_detected={};
    # Defining an error counter as 0 errors
    my $error=0;
    # a hash reference containing a list of all of the possible error permutations
    my $confilcts={
	'flush'=>'compare,load,reload,save,syntax',
	'compare'=>'flush,load,reload,save,syntax',
	'load'=>'flush,compare,reload,save,syntax',
	'reload'=>'flush,compare,load,save,syntax',
	'save'=>'flush,compare,load,reload,syntax',
	'syntax'=>'flush,compare,load,reload,save',
    };
    # a hash reference containing the portion of any error messages that represent the parameter
    my $confilct_message={
	'flush'=>'-F or --Flush',
	'compare'=>'-C or --Checkrunning',
	'load'=>'-L or --Load',
	'reload'=>'-R or --Reload',
	'save'=>'-S or --Save',
	'syntax'=>'-s or --validatesyntax',
    };
    # looping through the options specified
    for my $key (keys %{$options}){
	# making sure to only check options which have been set that have know conflicts with other options
	if (defined $options->{$key} and $options->{$key} and defined $confilcts->{$key}){
	    # splitting the list of possible conflicts into an array
	    my @option_conflicts=split(',',$confilcts->{$key});
	    # looping through the list of possible conflicts
	    for my $conflict (@option_conflicts){
		# testing if a conflicting option has been defined
		if (defined $options->{$conflict} and $options->{$conflict}){
		    # marking the conflicting option as having a known conflict so it doesn't get tested a second time
		    $conflicts_detected->{$conflict}=1;
		    # notifying the user of the conflict
		    warn "ERROR: options $confilct_message->{$key} conflict with $confilct_message->{$conflict}\n";
		    # Incrementing the error counter
		    $error++;
		}
	    }
	}
    }
    # checking if there were any conflicts found
    if ($error){
	# returning the number of conflicts
	return $error;
    }
}

# will be used latter
sub verbose_print{
    my $options=shift;
    my $level=shift;
    my $message=shift;
    chomp($message);
    if (defined $options->{'verbose'} and $level >= $options->{'verbose'}){
	print "$message\n";
    }
}

# This function returns a hash reference the keys for which are the list of all of the sets currently defined in the kernel
# It requires 1 parameter a hash reference containing the parsed command line options
# returns a hash reference containing the name of each set in the kernel as a key in the hash
sub list_running_set_names($){
    # the hash reference containing the parsed command line options
    my $options=shift;
    # getting the raw list of set names in the kernel
    my $raw=`$options->{'path'} list -name`;
    # ensuring there are sets defined based on the raw name dump
    if (defined $raw){
	# defining an empty hash reference that will contain the resulting list of set names
	my $results={};
	# Looping through each set name
	for my $name (split(/\n/,$raw)){
	    # removing any extraneous line breaks 
	    chomp($name);
	    # defining a key with the name of the set as Boolean true(1)
	    $results->{$name}=1;
	}
	# 3returning the resulting hash reference
	return $results;
    }
}

# This function creates and populates a new set
# this command requires 3 parameters
# 1) The name of the set to be created
# 2) A hash reference containing the data needed to create and populate the set
# 3) A hash containing the parsed the command line options
# This function returns 1 on success and 0 on failure
sub create_set($$$){
    # The name of the set
    my $name=shift;
    # The hash reference containing the data to create and populate the set
    my $set=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # executing the command to create the set
    if(system($options->{'path'},'create',$name,$set->{'type'},@{$set->{'header'}})){
	# if there was an error executing the command warn the user
	warn "ERROR: failed to create set \"$name\"\n";
	# return 0 indicating a failure
	return 0;
    }
    # looping through the list of items to be added to the set
    for my $member (@{$set->{'members'}}){
	# executing the command to add a an item to the set
	if(system($options->{'path'},'add',$name,$member)){
	    # if the addition fails warn the user
	    warn "ERROR: failed to add \"$member\" to set \"$name\"\n";
	    # return 0 indicating a failure
	    return 0;
	}
    }
    # if all of the commands to create and populate the set were executed successfully return 1 indicating success
    return 1;
}

# imitate creating a set note this is not currently used and may go away
sub smiulate_create_set($$$){
    my $name=shift;
    my $set=shift;
    my $options=shift;
    my $output='';
    if(defined $options->{'dryrun'} and $options->{'dryrun'}){
	$output=join(' ',$options->{'path'},'create',$name,$set->{'type'},@{$set->{'header'}},"\n");
	for my $member (@{$set->{'members'}}){
	    $output=$output . join(' ',$options->{'path'},'add',$name,$member,"\n");
	}
    }
    else{
	$output=join(' ','create',$name,$set->{'type'},@{$set->{'header'}},"\n");
	for my $member (@{$set->{'members'}}){
	    $output=$output . join(' ','add',$name,$member,"\n");
	}
    }
    return $output;
}

# This function updates a set without interruption it does this by creating and populating a temporary set
# Next it swaps the content of the temporary and currently running set.
# Finally it deletes the temporary set containing the old data
# this command requires 3 parameters
# 1) The name of the set to be updated
# 2) A hash reference containing the data needed to create and populate the set
# 3) A hash containing the parsed the command line options
# This function returns 1 on success and 0 on failure
sub update_set($$$){
    # The name of the set
    my $name=shift;
    # The hash reference containing the data to create and populate the set
    my $set=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # creating the name to use for the temporary set
    my $tempname=$name . '-temp';
    # executing the command to create the temporary set
    if(system($options->{'path'},'create',$tempname,$set->{'type'},@{$set->{'header'}})){
	# if there was an error executing the command warn the user
	warn "ERROR: failed to create the temporary set \"$tempname\"\n";
	# return 0 indicating a failure
	return 0;
    }
    # looping through the list of items to be added to the temporary set
    for my $member (@{$set->{'members'}}){
	# executing the command to add a an item to the temporary set
	if(system($options->{'path'},'add',$tempname,$member)){
	    # if there was an error executing the command warn the user
	    warn "ERROR: failed to add \"$member\" to the temporary set \"$tempname\"\n";
	    # Deleting the temporary set
	    delete_set($tempname,$options);
	    # return 0 indicating a failure
	    return 0;
	}
    }
    # swapping the contents of the temporary set with those of the running set
    if (system($options->{'path'},'swap',$tempname,$name)){
	# if there was an error executing the command warn the user
	warn "ERROR: Unable to swap set \"$tempname\" with \"$name\"\n";
	# Deleting the temporary set
	delete_set($tempname,$options);
	# return 0 indicating a failure
	return 0;
    }
    # Deleting the temporary set
    if (delete_set($tempname,$options)){
	# If successful return 1 indicating success
	return 1;
    }
    else{
	# if there was an error executing the command warn the user
	warn "ERROR: unable to delete the temporary set \"$tempname\"\n";
	# return 0 indicating a failure
	return 0;
    }
}

# This function deletes a set from the kernel
# The function requires two parameters
# 1) the name of the set
# 2) a hash reference containing the CLI options
# This function returns 1 on success and 0 on failure
sub delete_set($$){
    # The name of the set
    my $name=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # executing the command to delete the set
    if (system($options->{'path'},'destroy',$name)){
	# if there was an error executing the command warn the user
	warn "ERROR: Unable to delete set \"$name\"\n";
	# return 0 indicating a failure
	return 0;
    }
    # If successful return 1 indicating success
    return 1;
}

# This function compares the parsed XML of a configures set to that of the parsed XML of a set in the kernel
# This function requires four parameters
# 1) the name of the set to compare
# 2) a hash reference containing the parsed and formatted configuration
# 3) a hash reference containing the parsed and formatted sets from the kernel
# 4) a hash reference containing the parsed command line options
# This function returns 1 on success and 0 on failure
sub compair_set($$$$){
    # The name of the set to compare
    my $name=shift;
    # hash reference containing the parsed and formatted configuration
    my $sets=shift;
    # hash reference containing the parsed and formatted sets from the kernel
    my $running_sets=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # creating a counter of differences found set to 0 differences 
    my $differences=0;
    # defining an empty hash reference that will be used to de-duplicate detected errors
    my $skip={};
    # Looping through all of the member entries for the set in the configuration file
    for my $src_member (@{$sets->{$name}->{'members'}}){
	# creating a boolean set to 0 (FALSE) indicating if a match has been found
	my $found=0;
	# Looping through the member entries in the kernel version of the set
	for my $runing_member (@{$running_sets->{$name}->{'members'}}){
	    # if a match has already been found stop checking
	    unless($found){
		# comparing the the member entries
		if ($runing_member =~ /^$src_member$/ and $src_member =~ /^$runing_member$/){
		    # if found increment the boolean to indicate TRUE
		    $found++;
		    # indicating that the entry has been checked so there is no need to compare this entire again when checking the kernel
		    $skip->{$src_member}=1;
		}
	    }
	}
	# check if there was a match found
	unless ($found){
	    # indicating that the entry has been checked so there is no need to compare this entire again when checking the kernel
	    $skip->{$src_member}=1;
	    # notifying the user
	    warn "Error: could not find a match for \"$src_member\" in the running set \"$name\" in the kernel\n";
	    # incrementing the difference counter
	    $differences++;
	}
    }
    # Looping through the member entries in the kernel version of the set
    for my $runing_member (@{$sets->{$name}->{members}}){
	# creating a boolean set to 0 (FALSE) indicating if a match has been found
	my $found=0;
	# if a match has already been found stop checking
	unless(defined $skip->{$runing_member}){
	    # Looping through all of the member entries for the set in the configuration file
	    for my $src_member(@{$running_sets->{$name}->{members}}){
		# if a match has already been found stop checking
		unless ($found){
		    # comparing the the member entries
		    if ($runing_member =~ /^$src_member$/ and $src_member =~ /^$runing_member$/){
			# if found increment the boolean to indicate TRUE
			$found++;
		    }
		}
	    }
	    # check if there was a match found
	    unless ($found){
		# notifying the user
		warn "Error: could not find a match for kernel entree \"$runing_member\" in the configuration file for set \"$name\"\n";
		 # incrementing the difference counter
		$differences++;
	    }
	}
    }
    # looping through the other tags in the configuration
    for my $tag (keys %{$sets->{$name}}){
	# don't bother with members or the header because the members have bee checked already and the header can be checked via the headerkeys
	unless ($tag =~/^(members|header)$/){
	    # only continue if the set exist in the kernel
	    if (defined $running_sets->{$name}){
		# check if the tag is the headerkeys tag
		if ($tag =~/^headerkeys$/){
		    # looping through each header field in the configuration for the set
		    for my $header(keys %{$sets->{$name}->{$tag}}){
			# checking if the header field in defined in the kernel
			if (defined $running_sets->{$name}->{$tag}->{$header}){
			    # checking if the values of the configured header key and the kernels header key match
			    unless ($sets->{$name}->{$tag}->{$header} =~ /^$running_sets->{$name}->{$tag}->{$header}$/){
				# if they don't match notify the user
				warn "ERROR: configured \"$header\" = \" \"$sets->{$name}->{$tag}->{$header}\" doesn't match kernel \"$header\" = \" \"$running_sets->{$name}->{$tag}->{$header}\" for set \"$name\"\n";
				# incrementing the difference counter
				$differences++;
			    }
			}
			# if the configured header key doesn't exist in the kernel
			else{
			    # notify the user
			    warn "ERROR: configured \"$header\" = \" \"$sets->{$name}->{$tag}->{$header}\" is not defined in the kernel\n";
			    # incrementing the difference counter
			    $differences++;
			}
			# mark the key not to be checked again
			$skip->{$header}=1;
		    }
		}
		# if its not the headerkey tag
		else{
		    # check if the value in the configuration matches the one in the kernel
		    unless ($sets->{$name}->{$tag} =~ /^$running_sets->{$name}->{$tag}$/){
			# notify the user if they don't match
			warn "ERROR: configured \"$tag\" = \" \"$sets->{$name}->{$tag}\" doesn't match kernel \"$tag\" = \" \"$running_sets->{$name}->{$tag}\" for set \"$name\"\n";
			# incrementing the difference counter
			$differences++;
		    }
		    # mark the key not to be checked again
		    $skip->{$tag}=1;
		}
	    }
	    # if the tag is not defined in the kernel
	    else{
		# mark the key not to be checked again
		$skip->{$tag}=1;
		# notify the user
		warn "ERROR: configured \"$tag\" = \" \"$sets->{$name}->{$tag}\" is not defined in the kernel\n";
		# incrementing the difference counter
		$differences++;
	    }
	}
    }
    # looping through the other tags in the kernel
    for my $tag (keys %{$running_sets->{$name}}){
	# don't bother with members or the header because the members have bee checked already and the header can be checked via the headerkeys
	unless ($skip->{$tag} or $tag =~/^(members|header)$/){
	    # only continue if the set exist in the configuration file
	    if (defined $sets->{$name}){
		# check if the tag is the headerkeys tag
		if ($tag =~/^headerkeys$/){
		    # looping through each header field in the kernel for the set
		    for my $header(keys %{$running_sets->{$name}->{$tag}}){
			# skip header fields that have already been checked
			unless (defined $skip->{$header}){
			    # checking if the header field in defined in the configuration file
			    if (defined $sets->{$name}->{$tag}->{$header}){
				# checking if the values of the configured header key and the kernels header key match
				unless ($sets->{$name}->{$tag}->{$header} =~ /^$running_sets->{$name}->{$tag}->{$header}$/){
				    # if they don't match notify the user
				    warn "ERROR: configured \"$header\" = \" \"$sets->{$name}->{$tag}->{$header}\" doesn't match kernel \"$header\" = \" \"$running_sets->{$name}->{$tag}->{$header}\" for set \"$name\"\n";
				    # incrementing the difference counter
				    $differences++;
				}
			    }
			    # if the configured header key doesn't exist in the configuration file
			    else{
				# notify the user
				warn "ERROR: configured \"$header\" = \" \"$sets->{$name}->{$tag}->{$header}\" is not defined in the kernel\n";
				# incrementing the difference counter
				$differences++;
			    }
			}
		    }
		}
		# if its not the headerkey tag
		else{
		    # check if the value in the configuration matches the one in the kernel or if it has already been checked
		    unless (defined $skip->{$tag} or $sets->{$name}->{$tag} =~ /^$running_sets->{$name}->{$tag}$/){
			# notify the user if they don't match
			warn "ERROR: configured \"$tag\" = \" \"$sets->{$name}->{$tag}\" doesn't match kernel \"$tag\" = \" \"$running_sets->{$name}->{$tag}\" for set \"$name\"\n";
			# incrementing the difference counter
			$differences++;
		    }
		}
	    }
	    # if the tag is not defined in the configuration file
	    else{
		# if it hasn't been reported already
		unless (defined $skip->{$tag}){
		    # notify the user
		    warn "ERROR: \"$tag\" = \" \"$running_sets->{$name}->{$tag}\" is defined in the kernel but not the configuration file\n";
		    # incrementing the difference counter
		    $differences++;
		}
	    }
	}
    }
    # if differences were found
    if ($differences){
	# notify the user how many were detected in the set
	warn "ERROR: $differences differences found in set \"$name\" \n";
	# return 0 indicating failure
	return 0;
    }
    # if no differences were detected
    else{
	# return 1 for success
	return 1;
    }
}

# This functions loads all of the sets in the configuration file into the kernel
# This function requires two parameters
# 1) A hash reference containing the parsed and formatted configuration information
# 2) A hash reference containing the parsed command line options
# This function returns 1 on success and 0 on failure
sub load_all_sets($$){
    # The hash reference containing the parsed and formatted configuration information
    my $sets=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # loop through the sets contained in the configuration file
    for my $set(keys %{$sets}){
	# call create_set to create the set in the kernel
	unless(create_set($set,$sets->{$set},$options)){
	    # notify the user if there was a failure during the process of creating the set
	    warn "ERROR: Aborting loading the sets from configuration file \"$options->{'config'}\" due to error in creating set \"$set\"\n";
	    # return 0 indicating failure
	    return 0;
	}
    }
    # return 1 for success
    return 1;
}

# This functions reloads all of the sets in the configuration file into the kernel without interruption of the exiting set
# It will also delete any sets in the kernel that no longer exist in the configuration file
# This function requires two parameters
# 1) A hash reference containing the parsed and formatted configuration information
# 2) A hash reference containing the parsed command line options
# This function returns 1 on success and 0 on failure
sub update_all_sets($$){
    # The hash reference containing the parsed and formatted configuration information
    my $sets=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # calling list_running_set_names to get a hash reference of the names of all of the sets in the kernel
    my $names=list_running_set_names($options);
    # Looping through the sets listed in the configuration file
    for my $set(keys %{$sets}){
	# If the set already exists in the kernel update it
	if (defined $names->{$set}){
	    # calling update_set to update the set in the kernel
	    unless(update_set($set,$sets->{$set},$options)){
		# notify the user if there was a failure during the process of updating the set
		warn "ERROR: Aborting reloading the sets from configuration file \"$options->{'config'}\" due to error in updating set \"$set\"\n";
		# return 0 indicating failure
		return 0;
	    }
	}
	# If the set doesn't already exist in the kernel create it
	else{
	    # call create_set to create the set in the kernel
	    unless(create_set($set,$sets->{$set},$options)){
		# notify the user if there was a failure during the process of creating the set
		warn "ERROR: Aborting reloading the sets from configuration file \"$options->{'config'}\" due to error in creating set \"$set\"\n";
		# return 0 indicating failure
		return 0;
	    }
	}
    }
    # loop through the list of sets in the kernel
    for my $set (keys %{$names}){
	# if the set exists in the kernel but not in the configuration delete it
	unless (defined $sets->{$set}){
	    # call delete_set to delete the set from the kernel
	    unless (delete_set($set,$options)){
		# notify the user if there was a failure during the process of deleting the set
		warn "ERROR: Aborting because set \"$set\" could not be deleted\n";
		# return 0 indicating failure
		return 0;
	    }
	}
    }
    # return 1 for success
    return 1;
}

# This function compares all of the sets in the configuration file and the kernel and reports on their differences
# it requires two parameters
# 1) A hash reference containing the parsed and formatted configuration information
# 2) A hash reference containing the parsed command line options
# if all sets match it will exit the application with a 0 indicating to the calling shell it was a success
# if differences are detected it will exit the application with a 1 indicating to the calling shell it was a failure
sub compare_all_sets($$){
    # The hash reference containing the parsed and formatted configuration information
    my $sets=shift;
    # The hash reference containing the parsed command line options
    my $options=shift;
    # Defining a counter for the number of differences detected set to 0
    my $differences=0;
    # defining an empty hash reference that will be used to de-duplicate differences detected
    my $skip={};
    # Getting the current running configuration XML from the kernel and adding the missing <XML> and </XML> tags to prevent the parser from throwing off errors
    my $running_sets_raw='<XML>' . `$options->{'path'} list -o xml` . '</XML>';
    # Parsing the kernel configuration
    my $running_sets=check_configuration($running_sets_raw);
    # looping through all of the sets in the kernel
    for my $running_set(keys %{$running_sets}){
	# check if the set in the kernel is defined in the configuration file
	unless (defined $sets->{$running_set}){
	    # if the set is not defined in the configuration notify the user
	    warn "set \"$running_set\" not found in the configuration file\n";
	    # increment the differences counter
	    $differences++;
	}
    }
    # looping through all of the sets in the configuration file
    for my $configured_set (keys %{$sets}){
	# check if the set in the configuration file is defined in the kernel
	unless (defined $running_sets->{$configured_set}){
	    # if the set is not defined in the kernel notify the user
	    warn "set \"$configured_set\" found in the configuration file but not in the kernel\n";
	    # increment the differences counter
	    $differences++;
	    # mark it in the skip hash as true because there is no point comparing against a set that doesn't exist in the kernel
	    $skip->{$configured_set}=1;
	}
	else{
	    # mark it in the skip hash as false so it will be compared in more depth
	    $skip->{$configured_set}=0;
	}
    }
    # looping through all of the sets in the configuration file
    for my $configured_set (keys %{$sets}){
	# don't check try to compare a set in the configuration if we already know it doesn't exist in the kernel
	unless($skip->{$configured_set}){
	    # call compair_set to check for differences
	    unless (compair_set($configured_set,$sets,$running_sets,$options)){
		# if differences were found notify the uses
		warn "ERROR: Found differences in set \"$configured_set\"\n";
		# increment the differences counter
		$differences++;
	    }
	}
    }
    # if differences are detected exit the application with a code of 1 
    if ($differences){
	# exiting with errors
	exit 1;
    }
    # otherwise exit the application with a code of 0
    else{
	# notify the user that all sets match
	print "All sets matched\n";
	# exit the application with no errors
	exit 0;
    }
}

# This function flushes the content of all the sets but does not delete them so things like iptables rules that reference them won't break
# it requires one parameter
# 1) A hash reference containing the parsed command line options
# This function returns 1 on success and 0 on failure
sub flush_all_sets($){
    # The hash reference containing the parsed command line options
    my $options=shift;
    # execute the ipset flush command
    if (system($options->{'path'},'flush')){
	# if there was an error executing the command notify the user
	warn "ERROR: could not flush the current ipsets";
	# return 0 indicating failure
	return 0;
    }
    # if the command executes successfully 
    else {
	# return 1 indicating success
	return 1;
    }
}

#==========================================================================================
# BEGIN SUBROUTINE BLOCK
#==========================================================================================

#==========================================================================================
# BEGIN OPTION PARSING BLOCK
#==========================================================================================


# setting the default parameters
my $defaults={
    'path'=>'/sbin/ipset', # The default location for the ipset command
    'config'=>'/etc/ipset.conf' # The default location for the configuration file
};
# getting the effective uid
my $uid = getpwuid($>);
# only run as root
unless ($uid eq 'root'){
    # Immediately exit if this command is not being run as root.
    die "ERROR: permission denied ipset can only be managed by root\n";
}
# creating a placeholder for a hash ref that will contain the parsed options
my $options={};
# processing the CLI options with Getopt::Long
GetOptions(
    'c|configuration=s'=>\$options->{'config'},
    'C|Checkrunning'=>\$options->{'compare'},
    'F|flush'=>\$options->{'flush'},
    'L|Load'=>\$options->{'load'},
    'P|Path=s'=>\$options->{'path'},
    'R|Reload'=>\$options->{'reload'},
    'S|Save'=>\$options->{'save'},
    's|validatesyntax'=>\$options->{'syntax'},
    'v|verbose'=>\$options->{'verbose'},
    'V|Version'=>\$options->{'version'},
);
# creating a counter for any errors detected
my $errors=0;
# ensuring that at least one operation is defined
unless((defined $options->{'compare'} and $options->{'compare'})
	or (defined $options->{'flush'} and $options->{'flush'})
	or (defined $options->{'load'} and $options->{'load'})
	or (defined $options->{'reload'} and $options->{'reload'})
	or (defined $options->{'save'} and $options->{'save'})
	or (defined $options->{'syntax'} and $options->{'syntax'})
	or (defined $options->{'version'} and $options->{'version'})
	){
    # incrementing the error counter
    $errors++;
    # notifying the user
    warn "ERROR: no operation defined\n";
}
# unless the user has defined a path to the ipset command set it to the default
unless(defined $options->{'path'} and $options->{'path'}){
    # setting the value to the default
    $options->{'path'}=$defaults->{'path'};
    
}
# ensuring that the ipset command exits and is executable
unless ( -f $options->{'path'} and -x $options->{'path'}){
    # if not notify the user
    warn "ERROR: could not find the ipset command located at \"$options->{'path'}\"\n";
    #incrementing the error counter
    $errors++;
}

# unless the user has defined a path to the configuration file set it to the default
unless(defined $options->{'config'} and $options->{'config'}){
    # setting the value to the default
    $options->{'config'}=$defaults->{'config'};
    
}
# check for any options specified that aren't defined usable options
if ($ARGV){
    # notify the user
    warn "ERROR: options \"@ARGV\" are invalid\n";
    # increment the error counter
    $errors++;
}
# if there were any errors detected so far die and indicate failure
if ($errors){
    # exits and notifying the user why
    die "CRITICAL: Exiting due errors\n";
}

#==========================================================================================
# END OPTION PARSING BLOCK
#==========================================================================================

#==========================================================================================
# BEGIN MAIN LOOP BLOCK
#==========================================================================================

# defining a scoped placeholder for the configuration information
my $sets;
# if the user wants to know the version of the script tell them
if (defined $options->{'version'}){
    # telling the user the version number
    print "$VERSION\n";
    # exit the application with no errors
    exit 0;
}
# if the user wants to compare the configuration with the kernel
elsif (defined $options->{'compare'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # calling check_configuration_file to check parse and format the configuration data
    $sets=check_configuration_file($options->{'config'});
    # font go any further if errors have already been detected
    unless ($conflict_count or $errors){
	# check if the configuration file parsed correctly
	if (defined $sets and $sets){
	    # calling compare_all_sets to compare all the sets in the configuration file with all of the sets in the kernel
	    compare_all_sets($sets,$options);
	}
	# if the configuration file was not parsed correctly
	else{
	    # increment the error counter
	    $errors++;
	}
    }
    # if there is a conflict or error
    else{
	# increment the error counter
	$errors++;
    }
}
# if the user wants to flush the sets in kernel
elsif (defined $options->{'flush'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # font go any further if errors have already been detected
    unless ($conflict_count  or $errors){
	# call flush_all_sets to flush the sets in kernel
	unless (flush_all_sets($options)){
	    # if it fails increment the error counter
	    $errors++;
	}
    }
    # if there is a conflict or error
    else{
	# increment the error counter
	$errors++;
    }
}
# if the user wants to load all of sets in the configuration file into kernel
elsif (defined $options->{'load'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # calling check_configuration_file to check parse and format the configuration data
    $sets=check_configuration_file($options->{'config'});
    # font go any further if errors have already been detected
    unless ($conflict_count  or $errors){
	# check if the configuration file parsed correctly
	if (defined $sets and $sets){
	    # calling load_all_sets to load all of sets in the configuration file into kernel
	    unless (load_all_sets($sets,$options)){
		# if it fails increment the error counter
		exit 1;
	    }
	}
	# if the configuration file was not parsed correctly
	else{
	    # increment the error counter
	    $errors++;
	}
    }
    # if there is a conflict or error
    else{
	# increment the error counter
	$errors++;
    }
}
# if the user wants to reload all of sets in the configuration file into kernel
elsif (defined $options->{'reload'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # calling check_configuration_file to check parse and format the configuration data
    $sets=check_configuration_file($options->{'config'});
    # font go any further if errors have already been detected
    unless ($conflict_count  or $errors){
	# check if the configuration file parsed correctly
	if (defined $sets and $sets){
	    # calling update_all_sets to reload all of sets in the configuration file into kernel
	    unless (update_all_sets($sets,$options)){
		# if it fails increment the error counter
		exit 1;
	    }
	
	}
	# if the configuration file was not parsed correctly
	else{
	    # increment the error counter
	    $errors++;
	}
    }
    # if there is a conflict or error
    else{
	# increment the error counter
	$errors++;
    }
}
elsif (defined $options->{'save'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # font go any further if errors have already been detected
    unless ($conflict_count or $errors){
	# getting the current configuration of the sets in the kernel in XML format
	my $running_config=`$options->{'path'} list -o XML`;
	# getting rid of any extraneous white space at the end
	chomp($running_config);
	# removing any instances of the references tag because its counter of things like iptables rules that utilize the set so we font care about for recreating sets
	$running_config=~s/\n\s*<references>\d+<\/references>\s*\n/\n/g;
	# removing any instances of the memsize tag because its a counter of how much ram the set is currently using so we font care about for recreating sets
	$running_config=~s/\n\s*<memsize>\d+<\/memsize>\s*\n/\n/g;
	# adding the missing <XML> and </XML> tags to prevent XML parsers from throwing off errors
	my $xml='<XML>' . "\n" . $running_config . "\n" . '</XML>';
	# opening file handle for the configuration file in over write mode
	open(CONFIG,'>',$options->{'config'});
	# writing the configuration file
	print CONFIG $xml;
	# closing the file handle
	close(CONFIG);
    }
    else{
	# increment the error counter
	$errors++;
    }
}
elsif (defined $options->{'syntax'} ){
    # calling cli_confilct_check detect command line option conflicts
    my $conflict_count=cli_confilct_check($options);
    # calling check_configuration_file to check parse and format the configuration data
    $sets=check_configuration_file($options->{'config'});
    # font go any further if errors have already been detected
    unless ($conflict_count or $errors){
	# check if the configuration file parsed correctly
	if (defined $sets and $sets){
	    # do nothing
	}
	# if the configuration file was not parsed correctly
	else{
	    # increment the error counter
	    $errors++;
	}
    }
    # if there is a conflict or error
    else{
	# increment the error counter
	$errors++;
    }
}

# if there were any errors 
if ($errors){
    # exit with a warning and indicate the failure to the shell
    die "CRITICAL: Exiting due errors\n";
}


#==========================================================================================
# END MAIN LOOP BLOCK
#==========================================================================================

#==========================================================================================
# BEGIN POD DOCUMENTATION BLOCK
#==========================================================================================

=head1 NAME

=over 4

B<IPSet-Manager.pl> - Utility to utilize and manage IPset

=back

=head1 SYNOPSIS

=over 4
 
 IPSet-Manager.pl [-P /sbin/ipset ] [ -c /etc/ipset.xml ] [ -v ] ( -C | -F | -L |-R |-S | -s -V )
 
 =back
 
 =head1 DESCRIPTION
 
 =over 4
  
    IPSet-Manager.pl is a tool for managing ipsets in the Linux Kernel. It allows you to save, load, reload, and flush ipsets in the kernel. In addition you may also comapre a saved configuration file with whats currently in the kernel.
 
=back
 
=over 4
 
=item -P or --Path

The path to the ipset binary defaults to /sbin/ipset

=item -c or --configuration

The path to the XML configuration file defautls to /etc/ipset.xml

=item -C or --Checkrunning

Compares the content of the configuration with the sets currently in the kernel

=item -F or --Flush

Clears the content of all the sets in the kernel but does not delete them

=item -L or --Load

initialy loads the sets from the configuration file into the kernel
B<WARNING> this should only be used in very specific senarios where the sets dont currently exist in the kernel all other cases -R or --Reload should be used instead

=item -R or --Reload

Relaods a configuration into the kernel this will create new sets, update exiting ones without interution and delete obsolite sets,

=item -S or --Save

Saves the current ipstes in the kernel to the configuration file

=item -s or --validatesyntax

Checks the syntax of the configuraton file
B<WARNING> this has only been partioaly implemented at this time

=item -v or --verbose

Prints more verbose messages about what the tool is actually doing

=item -V or --Version

Prints the version number and exits

=back

=head1 EXAMPLES

=over 4

=item Saving a configuration

IPSet-Manager.pl -S

=item Saving a configuration file to an alternate location

IPSet-Manager.pl -S -c /etc/sysconfig/ipset

=item Loading a configuration after boot

IPSet-Manager.pl -L

=item Reloading a configuration after an update to the configuration

IPSet-Manager.pl -R

=item Clearing the contents of all of the ipsets in the kernel

IPSet-Manager.pl -F

=item Checking the sysntax of a configuration file in an alternative location

IPSet-Manager.pl -s -c /etc/sysconfig/ipset

=item 

=back
