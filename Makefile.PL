require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;

WriteMakefile (
 NAME		=> "Thread::Pool::Resolve",
 ($[ >= 5.005) ?
 (AUTHOR	=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
  ABSTRACT	=> 'resolve logs asynchronously') : (),
 VERSION_FROM	=> 'lib/Thread/Pool/Resolve.pm',
 PREREQ_PM	=> {
                    'Thread::Pool' => '0.23',
                   },
);
