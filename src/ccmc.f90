module ccmc

! Module  for performing coupled cluster Monte Carlo (CCMC) calculations).

! Due to the similarities with FCIQMC, we can re-use lots of the same routines
! (especially the spawning, death and annihilation).  As a result, the structure
! of do_ccmc is remarkably similar to the other do_*mc routines.

! NOTE:
!     FCIQMC routines work entirely in a determinant framework.  This is
!     somewhat inconsistent with coupled cluster which is most naturally defined
!     in terms of excitors.  Thus when considering the interface between CC
!     routines and FCI routines, one should mentally translate 'Slater
!     determinant' into 'the Slater determinant formed by applying the excitor
!     to the reference determinant'.

! Numerous discussions with Alex Thom (AJWT) and access to drafts/preprints of
! AJWT's CCMC papers gratefully acknowledged.  The following comments are some
! useful implementation notes that fill in some technical details not (yet)
! explicitly described in the CCMC papers.

! CCMC
! ====
!
! In the following, a capital index refers to combined index (ie a single label
! for a determinant or excitor) and a lower case index referis to a spin
! orbital.  Hence |D_I> can be equivalently represented as |D_{ij...}^{ab..}.
!
! Analogue with FCIQMC
! --------------------
!
! In FCIQMC we essentially use first-order finite-difference approximation to the
! imaginary-time Schroedinger equation::
!
!     c_I(t+dt) = c_I(t) - < D_I | H - S | \Psi(t) > dt  (1)
!
! where::
!
!     \Psi(t) = \sum_J c_J(t) | D_J >.  (2)
!
! CCMC involves propogating a very similar equation::
!
!     < D_I | a_I D_0 > t_I(t+dt) = < D_I | a_I D_0 > t_I(t) - < D_I | H - S | \Psi_{CC}(t) > dt  (3)
!
! where::
!
!     \Psi_{CC}(t) = e^{T(t)} | D_0 >,  (4)
!
! and the cluster operator, T, is::
!
!     T(t) = \sum_{ia} t_i^a(t) a_i^a + 1/2!^2 \sum_{ijab} t_{ij}^{ab}(t) a_{ij}^{ab} + ...  (5)
!
! (I apologise for using a in two different senses...)
!
! The operators, {a_I=a_{ij...}^{ab...}}, known as excitors, cause electrons to
! be excited from occupied orbitals in the reference determinant to virtual
! orbitals and have corresponding amplitudes, {t_I}, which evolve in time.  In
! the infinite-time limit, the amplitudes converge onto the true CC
! wavefunction.
!
! Note that, depending upon the definition of a_I, < D_I | a_I D_0 > can be
! either +1 or -1.  Alex Thom defines a_I such that this term is always +1 in his
! CCMC papers but this definition is not convenient for computation.  See
! comments in collapse_cluster and convert_excitor_to_determinant.
!
! We can only handle uniquely defined excitors, i.e. we consider t_{ij}^{ab}, 
! t_{ji}^{ba}, t_{ji}^{ab} and t_{ij}^{ba} to be one entity.  This is fine as
! t_{ij}^{ab} a_{ij}^{ab} = t_{ji}^{ba} a_{ji}^{ba} = -t_{ji}^{ab} = -t_{ij}^{ba}.
! As a consequence, we must be very careful with the above expansion in (5).  We
! can simplify (5) such that each unique cluster only occurs once::
!
!     T(t) = \sum_{ia} t_i^a(t) a_i^a + \sum_{i<j,a<b} t_{ij}^{ab}(t) a_{ij}^{ab} + ...  (6)
!
! Evaluating e^{T(t)} is, as in traditional CC, performed using a series
! expansion::
!
!     e^{T(t)} = e^{\sum_I t_I a_I}                                           (7)
!              = 1 + sum_I t_I a_I + 1/2! sum_{IJ} t_I t_J a_I a_J + ...      (8)
!
! Alternatively, as pointed out by Trygve Helgaker, one can consider::
!
!     e^{T(t)} = e^{t_I(t) a_I} e^{t_J(t) a_J} e^{t_K(t) a_K} ...             (9)
!              = (1+t_I(t) a_I) (1+t_J(t) a_J) (1+t_K(t) a_K) ...             (10)
!
! which expands out to (8), except for the absence of the factorial prefactors,
! and uses the property that a_I a_I = 0.  However, there is no computational
! advantage to using this and, due to the need to consider an order for {I}, it
! is actually trickier to code than using (8).
!
! Normalisation
! -------------
!
! The convention that the overlap with the reference is set to unity is rather
! hard to maintain in CCMC.  Instead we follow the prescription of Alex Thom and
! introduce an additional variable, N_0, to act as a normalisation constant::
!
!     |\Psi_{CC}> = N_0 e^{T/N_0} | D_0 >    (11)
!
! The number of particles on the reference (not strictly excips though we shall
! refer to them by this name for the sake of conciseness and generality) is
! hence N_0 and can be varied stochastically to maintain the required
! (relative) normalisation.
!
! Dynamics
! --------
!
! Dynamics in FCIQMC involve stochastically sampling the action of the
! Hamiltonian.  As the projection onto the CC wavefunction in (3) involves many
! terms (higher-order 'clusters' of excitors), CCMC also requires one to
! stochastically sample the CC wavefunction itself.  This results in a process
! similar (but more complicated) than the FCIQMC dynamics.  The similarities are
! such that we can reuse much of the FCIQMC routines, including the excitation
! generators and annihilation procedures.
!
! The CC wavefunction can be sampled by selected a random cluster of excitors.
! Applying this cluster to the reference determinant generates a determinant,
! D_I.  The action of the Hamiltonian is sampled in an identical fashion to
! FCIQMC:
!
! #. Generate D_J, a random (single or double) excitation of D_I.  Create a new
!    particle on D_J with a probability proportional to |H_{IJ}| dt.
! #. Create a particle on D_I with a probability proportional to |H_{II}-S| dt.
!
! As with FCIQMC, because we do not allow every possible event to take place each
! iteration, the probabilities must be weighted accordingly by the probability
! that the event was selected.
!
! After we have sampled the CC wavefunction and sampled its evolution the desired
! number of times, we then annihilate all particles (excips) on the same excitor
! with opposite signs.
!
! There are two main differences between FCIQMC and CCMC evolution.  As the FCI
! wavefunction is a linear combination of determinants, we can simply loop over
! all particles (psips) on the determinants and allow them to spawn and die.  As
! the CC wavefunction ansatz involves an exponentiation, we must consider
! combinations of excitors and hence combinations of excips.  The stochastic
! sampling of the wavefunction is achieved by selecting random clusters;
! hopefully the comments in select_cluster provide suitable illumination.
!
! The other main difference (and certainly the hardest to get right) is that the
! signs of the excips and their progeny are *far* more subtle and involved than
! in FCIQMC.  In addition to the explicit minus sign in the propogation equation
! (3), the other sources of sign changes are:
!
! #. the sign of the excip from which a new excip is spawned/cloned/killed (also
!    in FCIQMC).  Note that the amplitude of the excips on a cluster of excitors
!    is the product of the amplitudes of the excips on the individual excitors.
! #. the sign of the Hamiltonian matrix element (also in FCIQMC).
! #. combining excitors to form a 'cluster' excitor requires reordering of the
!    set of annihilation and creation operators.  Each permutation causes a sign
!    change and thus an overall odd number of permutations causes a sign change
!    in the excip population.  See collapse_cluster.
! #. Applying the I-th excitor to D_0 can result in a sign change due to the
!    different definitions of an excitor and determinant which also requires
!    permutations of creation and annihilation operators.  See
!    convert_excitor_to_determinant.
! #. As we are creating an excip on the J-th excitor from the I-th excitor, we
!    must be consistent with our definition of the excitor; in particular they
!    might produce determinants of different signs when applied to the reference
!    determinant.  Thus if we consider creating an excip on t_J from t_I (where
!    J can be I or any connected excitor), we *must* take into account the signs
!    of the excitors relative to the reference determinant.
!
! In order for the correct dynamics to be performed, we must carefully
! accumulate all negative signs and take them into account when
! determining the sign of the child excips.

use const, only: i0, lint, p

implicit none

integer :: D0_normalisation

contains

    subroutine do_ccmc()

        ! Run the CCMC algorithm starting from the initial walker distribution
        ! using the timestep algorithm.

        ! See notes about the implementation of this using function pointers
        ! in fciqmc_main.

        use checking, only: check_allocate, check_deallocate
        use dSFMT_interface, only: dSFMT_t, dSFMT_init
        use errors, only: stop_all
        use utils, only: rng_init_info
        ! TODO: parallelisation.
        use parallel

        use annihilation, only: direct_annihilation
        use basis, only: basis_length, nbasis
        use calc, only: seed, truncation_level, truncate_space
        use ccmc_data, only: cluster_t
        use determinants, only: det_info, alloc_det_info, dealloc_det_info
        use excitations, only: excit, get_excitation_level
        use fciqmc_data
        use qmc_common
        use fciqmc_restart, only: dump_restart
        use proc_pointers
        use search, only: binary_search
        use system, only: nel

        integer :: i, ireport, icycle, it
        integer(lint) :: iattempt, nattempts, nparticles_old(sampling_size)
        type(det_info), allocatable :: cdet(:)

        integer :: nspawned, ndeath, ierr
        type(excit) :: connection
        type(cluster_t), allocatable, target :: cluster(:)
        type(dSFMT_t), allocatable :: rng(:)
        real(p) :: junk

        logical :: soft_exit

        integer, allocatable :: cumulative_abs_pops(:)
        integer :: D0_pos, max_cluster_size,tot_abs_pop
        logical :: hit

        real :: t1, t2

        if (.not.truncate_space) then
            ! User did not specify a truncation level.
            ! We're hence doing Full CC (equivalent but more expensive than
            ! FCI), for reasons best known to the user---perhaps testing?
            ! Anyway, need to set truncation level as it's used in the
            ! select_cluster routine.
            truncation_level = nel
        end if

        if (truncation_level+2 > 12) then
            call stop_all('do_ccmc', 'CCMC can currently only handle clusters up &
                                     &to size 12 due to integer overflow in &
                                     &factorial routines for larger clusters.  Please &
                                     &implement better factorial routines.')
        end if

        ! Allocate and initialise per thread...
        allocate(rng(0:nthreads-1), stat=ierr)
        call check_allocate('rng', size(rng), ierr)
        if (parent) call rng_init_info(seed+iproc)
        allocate(cdet(0:nthreads-1), stat=ierr)
        call check_allocate('cdet', size(cdet), ierr)
        allocate(cluster(0:nthreads-1), stat=ierr)
        call check_allocate('cluster', size(cluster), ierr)
        do i = 0, nthreads-1
            ! Initialise and allocate RNG store.
            call dSFMT_init(seed+(iproc*nthreads)+i, 50000, rng(i))
            ! ...and allocate det_info components...
            call alloc_det_info(cdet(i))
            ! ...and cluster_t components
            allocate(cluster(i)%excitors(truncation_level+2), stat=ierr)
            call check_allocate('cluster%excitors', truncation_level+2, ierr)
        end do
        ! ...and scratch space for calculative cumulative probabilities.
        allocate(cumulative_abs_pops(walker_length), stat=ierr)
        call check_allocate('cumulative_abs_pops', walker_length, ierr)

        ! Whilst cluster data can be accessed from cdet, I recommend explicitly
        ! passing it as an argument rather than accessing cdet%cluster both for
        ! the sake of brevity and clarity.  In particular, I wish to encourage
        ! not using cdet%cluster in order to maintain (where possible and
        ! relevant) generality in routines applicable to FCIQMC and CCMC.
        do i = 0, nthreads-1
            cdet(i)%cluster => cluster(i)
        end do

        ! from restart
        nparticles_old = tot_nparticles

        ! Main fciqmc loop.
        if (parent) call write_fciqmc_report_header()
        call initial_fciqmc_status()
        ! Initialise timer.
        call cpu_time(t1)

        do ireport = 1, nreport

            call init_report_loop()

            do icycle = 1, ncycles

                ! Population on reference determinant.
                ! As we might select the reference determinant multiple times in
                ! a cycle, the running total of D0_population is incorrect (by
                ! a factor of the number of times it was selected).
                call binary_search(walker_dets, f0, 1, tot_walkers, hit, D0_pos)
                D0_normalisation = walker_population(1,D0_pos)

                ! Note that 'death' in CCMC creates particles in the spawned
                ! list, so the number of deaths not in the spawned list is
                ! always 0.
                call init_mc_cycle(nattempts, ndeath)

                ! Maximum possible cluster size that we can generate.
                ! Usually this is either the number of electrons or the
                ! truncation level + 2 but we must handle the case where we are
                ! growing the initial population from a single/small number of
                ! excitors.
                max_cluster_size = min(min(nel, truncation_level+2), tot_walkers-1)

                ! Find cumulative population...
                call cumulative_population(walker_population, tot_walkers, D0_pos, cumulative_abs_pops, tot_abs_pop)

                ! Allow one spawning & death attempt for each excip on the
                ! processor.
                ! OpenMP chunk size determined completely empirically from a single
                ! test.  Please feel free to improve...
                !$omp parallel private(it)
                it = get_thread_id()
                !$omp do schedule(dynamic,200) private(nspawned, connection, junk) reduction(+:D0_population_cycle,proj_energy)
                do iattempt = 1, nattempts

                    call select_cluster(rng(it), nattempts, D0_pos, cumulative_abs_pops, tot_abs_pop, max_cluster_size, &
                                        cdet(it), cluster(it))

                    if (cluster(it)%excitation_level <= truncation_level+2) then

                        ! FCIQMC calculates the projected energy exactly.  To do
                        ! so in CCMC would involve enumerating over all pairs of
                        ! single excitors, which is rather painful and slow.
                        ! Instead, as we are randomly sampling clusters in order
                        ! to evolve the excip population anyway, we can just use
                        ! the random clusters to *sample* the projected
                        ! estimator.  See comments in spawning.F90 for why we
                        ! must divide through by the probability of selecting
                        ! the cluster.
                        call update_proj_energy_ptr(f0, cdet(it), &
                                 cluster(it)%cluster_to_det_sign*cluster(it)%amplitude/cluster(it)%pselect, &
                                 D0_population_cycle, proj_energy, connection, junk)

                        call spawner_ccmc(rng(it), cdet(it), cluster(it), gen_excit_ptr, nspawned, connection)

                        if (nspawned /= 0) then
                            call create_spawned_particle_ptr(cdet(it), connection, nspawned, spawned_pop)
                        end if

                        ! Does the cluster collapsed onto D0 produce
                        ! a determinant is in the truncation space?  If so, also
                        ! need to attempt a death/cloning step.
                        if (cluster(it)%excitation_level <= truncation_level) then
                            call stochastic_ccmc_death(rng(it), cdet(it), cluster(it))
                        end if

                    end if

                end do
                !$omp end do
                !$omp end parallel

                call direct_annihilation()

                ! Ok, this is fairly non-obvious.
                ! Because we sample the projected estimator (and normalisation
                ! <D_0| \Psi_CC>) N times, where N is the number of excips, we
                ! must divide through be N in order to avoid introducing a bias.
                ! Not doing so means that the quality of the sampling of the sum
                ! (the space of which is constant) varies with population.  The
                ! bias is small but noticeable in some systems.
! JSS: Need to discuss with AJWT, but it looks like we should *not* normalise D0
! as well as proj_energy_cycle.
!                D0_population_cycle = D0_population_cycle/nattempts
                proj_energy_cycle = proj_energy_cycle/nattempts

                call end_mc_cycle(ndeath, nattempts)

            end do

            call end_report_loop(ireport, nparticles_old, t1, soft_exit)

            if (soft_exit) exit

        end do

        if (parent) then
            call write_fciqmc_final(ireport)
            write (6,'()')
        end if

        call load_balancing_report()

        if (soft_exit) then
            mc_cycles_done = mc_cycles_done + ncycles*ireport
        else
            mc_cycles_done = mc_cycles_done + ncycles*nreport
        end if

        if (dump_restart_file) call dump_restart(mc_cycles_done, nparticles_old)

        ! TODO: deallocation...
!        call dealloc_det_info(cdet)
!        cdet%cluster => NULL()
!        deallocate(cluster%excitors, stat=ierr)
!        call check_deallocate('cluster%excitors', ierr)

    end subroutine do_ccmc

    subroutine select_cluster(rng, nattempts, D0_pos, cumulative_excip_pop, tot_excip_pop, max_size, cdet, cluster)

        ! Select a random cluster of excitors from the excitors on the
        ! processor.  A cluster of excitors is itself an excitor.  For clarity
        ! (if not technical accuracy) in comments we shall distinguish between
        ! the cluster of excitors and a single excitor, from a set of which the
        ! cluster is formed.

        ! In:
        !    nattempts: the number of times (on this processor) a random cluster
        !        of excitors is generated in the current timestep.
        !    D0_pos: position in the excip list of the reference.
        !    cumulative_excip_population: running cumulative excip population on
        !        all excitors; i.e. cumulative_excip_population(i) = sum(walker_population(1:i)).
        !    tot_excip_pop: total excip population.

        ! NOTE: cumulative_excip_pop and tot_excip_pop ignore the population on
        ! the reference as excips on the reference cannot form a cluster.  Both
        ! these quantities should be generated by cumulative_population (or be
        ! in the same format).

        ! In/Out:
        !    rng: random number generator.
        !    cdet: information about the cluster of excitors applied to the
        !        reference determinant.  This is a bare det_info variable on input
        !        with only the relevant fields allocated.  On output the
        !        appropriate (system-specific) fields have been filled by
        !        decoding the bit string of the determinant formed from applying
        !        the cluster to the reference determinant.
        !    cluster:
        !        Additional information about the cluster of excitors.  On
        !        input this is a bare cluster_t variable with the excitors array
        !        allocated to the maximum number of excitors in a cluster.  On
        !        output all fields in cluster have been set.

        use calc, only: truncation_level
        use determinants, only: det_info
        use ccmc_data, only: cluster_t
        use excitations, only: get_excitation_level
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use fciqmc_data, only: f0, tot_walkers, walker_population, walker_dets, initiator_population
        use proc_pointers, only: decoder_ptr
        use utils, only: factorial
        use search, only: binary_search

        integer(lint), intent(in) :: nattempts
        integer, intent(in) :: D0_pos
        integer, intent(in) :: cumulative_excip_pop(:), tot_excip_pop, max_size
        type(dSFMT_t), intent(inout) :: rng
        type(det_info), intent(inout) :: cdet
        type(cluster_t), intent(inout) :: cluster

        real(p) :: rand, psize, cluster_population
        integer :: i, pos, pop, excitor_sgn
        logical :: hit, allowed

        ! We shall accumulate the factors which comprise cluster%pselect as we go.
        !   cluster%pselect = n_sel p_size p_clust
        ! where
        !   n_sel   is the number of cluster selections made (by this
        !           processor);
        !   p_size  is the probability of choosing a cluster of that size;
        !   p_clust is the probability of choosing a specific cluster given
        !           the choice of size.

        cluster%pselect = nattempts

        ! Select the cluster size, i.e. the number of excitors in a cluster.
        ! For a given truncation_level, only clusters containing at most
        ! truncation_level+2 excitors.
        ! Following the process described by Thom in 'Initiator Stochastic
        ! Coupled Cluster Theory' (unpublished), each size, n_s, has probability
        ! p(n_s) = 1/2^(n_s+1), n_s=0,truncation_level and p(truncation_level+2)
        ! is such that \sum_{n_s=0}^{truncation_level+2} p(n_s) = 1.
        rand = get_rand_close_open(rng)
        psize = 0.0_p
        cluster%nexcitors = -1
        do i = 0, max_size-1
            psize = psize + 1.0_p/2**(i+1)
            if (rand < psize) then
                ! Found size!
                cluster%nexcitors = i
                cluster%pselect = cluster%pselect/2**(i+1)
                exit
            end if
        end do
        ! If not set, then must be the largest possible cluster
        if (cluster%nexcitors == -1) then
            cluster%nexcitors = max_size
            cluster%pselect = cluster%pselect*(1.0_p - psize)
        end if

        ! Initiator approximation: no point using a CAS so just use the populations.
        ! This is sufficiently quick that we'll just do it in all cases, even
        ! when not using the initiator approximation.  This matches the approach
        ! used by Alex Thom in 'Initiator Stochastic Coupled Cluster Theory'
        ! (unpublished).
        ! Assume all excitors in the cluster are initiators (initiator_flag=0)
        ! until proven otherwise (initiator_flag=1).
        cdet%initiator_flag = 0

        ! Assume cluster is allowed unless collapse_cluster finds out otherwise
        ! when collapsing/combining excitors.
        allowed = .true.

        select case(cluster%nexcitors)
        case(0)
            ! Must be the reference.
            cdet%f = f0
            cluster%excitation_level = 0
            cluster%amplitude = D0_normalisation
            cluster%cluster_to_det_sign = 1
            if (cluster%amplitude <= initiator_population) then
                ! Something has gone seriously wrong and the CC
                ! approximation is (most likely) not suitably for this system.
                ! Let the user be an idiot if they want to be...
                cdet%initiator_flag = 1
            end if
            ! Only one cluster of this size to choose => p_clust = 1
        case default
            ! Select cluster from the excitors on the current processor with
            ! probability for choosing an excitor proportional to the excip
            ! population on that excitor.
            do i = 1, cluster%nexcitors
                ! Select a position in the excitors list.
                pop = int(get_rand_close_open(rng)*tot_excip_pop) + 1 ! TODO: adjust for parallel
                call binary_search(cumulative_excip_pop, pop, 1, tot_walkers, hit, pos)
                ! Not allowed to select the reference as it is not an excitor.
                ! Because we treat (for the purposes of the cumulative
                ! population) the reference to have 0 excips, then
                ! cumulative_excip_pop(D0_pos) = cumulative_excip_pop(D0_pos-1).
                ! The binary search algorithm assumes each value in the array
                ! being searched is unique, which is not true, so we can
                ! accidentally find D0_pos.  As we want to find pos such that
                ! cumulative_excip_pop(pos-1) < pop <= cumulative_excip_pop(pos),
                ! then this means we actually need the slot before D0_pos.
                ! Correcting for this accident is much easier than producing an
                ! array explicitly without D0...
                if (pos == D0_pos) pos = pos - 1
                if (i == 1) then
                    ! First excitor 'seeds' the cluster:
                    cdet%f = walker_dets(:,pos)
                    cluster_population = walker_population(1,pos)
                else
                    call collapse_cluster(walker_dets(:,pos), walker_population(1,pos), cdet%f, cluster_population, allowed)
                    if (.not.allowed) exit
                end if
                if (walker_population(1,pos) <= initiator_population) cdet%initiator_flag = 1
                ! Probability of choosing this excitor = pop/tot_pop.
                cluster%pselect = (cluster%pselect*abs(walker_population(1,pos)))/tot_excip_pop
                cluster%excitors(i)%f => walker_dets(:,pos)
            end do

            if (allowed) cluster%excitation_level = get_excitation_level(f0, cdet%f)
            ! To contribute the cluster must be within a double excitation of
            ! the maximum excitation included in the CC wavefunction.
            if (cluster%excitation_level > truncation_level+2) allowed = .false.

            if (allowed) then
                ! We chose excitors with a probability proportional to their
                ! occupation.  However, because (for example) the cluster t_X t_Y
                ! and t_Y t_X collapse onto the same excitor (where X and Y each
                ! label an excitor), the probability of selecting a given cluster is
                ! proportional to the number of ways the cluster could have been
                ! formed.  (One can view this factorial contribution as the
                ! factorial prefactors in the series expansion of e^T---see Eq (8)
                ! in the module-level comments.)
                cluster%pselect = cluster%pselect*factorial(cluster%nexcitors)

                ! Sign change due to difference between determinant
                ! representation and excitors and excitation level.
                call convert_excitor_to_determinant(cdet%f, cluster%excitation_level, cluster%cluster_to_det_sign)

                ! Normalisation factor for cluster%amplitudes...
                cluster%amplitude = cluster_population/(real(D0_normalisation,p)**(cluster%nexcitors-1))
            else
                ! Simply set excitation level to a too high (fake) level to avoid
                ! this cluster being used.
                cluster%excitation_level = huge(0)
            end if

        end select

        ! Fill in information about the cluster if required.
        if (cluster%excitation_level <= truncation_level+2) call decoder_ptr(cdet%f, cdet)

    end subroutine select_cluster

    subroutine spawner_ccmc(rng, cdet, cluster, gen_excit_ptr, nspawn, connection)

        ! Attempt to spawn a new particle on a connected excitor with
        ! probability
        !     \tau |<D'|H|D_s> A_s|
        !   -------------------------
        !   n_sel p_s p_clust p_excit
        ! where |D_s> is the determinant formed by applying the excitor to the
        ! reference determinant, A_s is the amplitude and D' is the determinant
        ! formed from applying a connected excitor to the reference determinant.
        ! See comments in select_cluster about n_sel, p_s and p_clust.  p_excit
        ! is the probability of choosing D' given D_s.

        ! This is just a thin wrapper around a system-specific excitation
        ! generator and a utility function.  We need to modify the spawning
        ! probability compared to the FCIQMC algorithm as we spawn from multiple
        ! excips at once (in FCIQMC we allow each psip to spawn individually)
        ! and have additional probabilities to take into account.

        ! In:
        !    cdet: info on the current excitor (cdet) that we will spawn
        !        from.
        !    cluster: information about the cluster which forms the excitor.  In
        !        particular, we use the amplitude, cluster_to_det_sign and pselect
        !        (i.e. n_sel.p_s.p_clust) attributes in addition to any used in
        !        the excitation generator.
        !    gen_excit_ptr: procedure pointer to excitation generators.
        !        gen_excit_ptr%full *must* be set to a procedure which generates
        !        a complete excitation.
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    nspawn: number of particles spawned.  0 indicates the spawning
        !        attempt was unsuccessful.
        !    connection: excitation connection between the current excitor
        !        and the child excitor, on which progeny are spawned.

        use basis, only: basis_length
        use ccmc_data, only: cluster_t
        use determinants, only: det_info
        use dSFMT_interface, only: dSFMT_t
        use excitations, only: excit, create_excited_det, get_excitation_level
        use fciqmc_data, only: f0
        use proc_pointers, only: gen_excit_ptr_t
        use spawning, only: attempt_to_spawn

        type(det_info), intent(in) :: cdet
        type(cluster_t), intent(in) :: cluster
        type(dSFMT_t), intent(inout) :: rng
        type(gen_excit_ptr_t), intent(in) :: gen_excit_ptr
        integer, intent(out) :: nspawn
        type(excit), intent(out) :: connection

        ! We incorporate the sign of the amplitude into the Hamiltonian matrix
        ! element, so we 'pretend' to attempt_to_spawn that all excips are
        ! actually spawned by positive excips.
        integer, parameter :: parent_sign = 1
        real(p) :: hmatel, pgen
        integer(i0) :: fexcit(basis_length)
        integer :: excitor_sign, excitor_level

        ! 1. Generate random excitation.
        ! Note CCMC is not (yet, if ever) compatible with the 'split' excitation
        ! generators of the lattice models.  It is trivial to implement and (at
        ! least for now) is left as an exercise to the interested reader.
        call gen_excit_ptr%full(rng, cdet, pgen, connection, hmatel)

        ! 2, Apply additional factors.
        hmatel = hmatel*cluster%amplitude*cluster%cluster_to_det_sign
        pgen = pgen*cluster%pselect

        ! 3. Attempt spawning.
        nspawn = attempt_to_spawn(rng, hmatel, pgen, parent_sign)

        if (nspawn /= 0) then
            ! 4. Convert the random excitation from a determinant into an
            ! excitor.  This might incur a sign change and hence result in
            ! a change in sign to the sign of the progeny.
            ! This is the same process as excitor to determinant and hence we
            ! can reuse code...
            call create_excited_det(cdet%f, connection, fexcit)
            excitor_level = get_excitation_level(f0, fexcit)
            call convert_excitor_to_determinant(fexcit, excitor_level, excitor_sign)
            if (excitor_sign < 0) nspawn = -nspawn
        end if

        if (abs(nspawn) > 5000) then
            write (6,*) '# WARNING: bloom', nspawn
            write (6,*) '# occ', cdet%occ_list
            write (6,*) '# cluster', cluster%nexcitors, cluster%excitation_level, cluster%amplitude, cluster%pselect
            write (6,*) '# connection', connection%from_orb(1:2), connection%to_orb(1:2)
            write (6,*) '# hmatel', hmatel/(cluster%amplitude*cluster%cluster_to_det_sign)
            write (6,*) '# pgen', pgen/cluster%pselect
        end if

    end subroutine spawner_ccmc

    subroutine stochastic_ccmc_death(rng, cdet, cluster)

        ! Attempt to 'die' (ie create an excip on the current excitor, cdet%f)
        ! with probability
        !    \tau |<D_s|H|D_s> A_s|
        !    ----------------------
        !       n_sel p_s p_clust
        ! where |D_s> is the determinant formed by applying the excitor to the
        ! reference determinant and A_s is the amplitude.  See comments in
        ! select_cluster about the probabilities.

        ! In:
        !    cdet: info on the current excitor (cdet) that we will spawn
        !        from.
        !    cluster: 
        !    amplitude: amplitude of cluster.
        !    pcluster: Overall probabilites of selecting this cluster, ie
        !        n_sel.p_s.p_clust.
        ! In/Out:
        !    rng: random number generator.

        use ccmc_data, only: cluster_t
        use determinants, only: det_info
        use fciqmc_data, only: tau, shift, spawned_pop, H00, f0
        use excitations, only: excit, get_excitation_level
        use proc_pointers, only: sc0_ptr
        use spawning, only: create_spawned_particle_truncated
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open

        type(det_info), intent(in) :: cdet
        type(cluster_t), intent(in) :: cluster
        type(dSFMT_t), intent(inout) :: rng

        real(p) :: pdeath, KiiAi
        integer :: nkill
        type(excit), parameter :: null_excit = excit( 0, [0,0,0,0], [0,0,0,0], .false.)

        ! Spawning onto the same excitor so no change in sign due to
        ! a difference in the sign of the determinant formed from applying the
        ! parent excitor to the reference and that formed from applying the
        ! child excitor.
        ! TODO: optimise for the case where the cluster is either the reference
        ! determinant or consisting of a single excitor.
        KiiAi = (sc0_ptr(cdet%f) - H00 - shift)*cluster%amplitude

        pdeath = tau*abs(KiiAi)/cluster%pselect

        ! Number that will definitely die
        nkill = int(pdeath)

        ! Stochastic death...
        pdeath = pdeath - nkill
        if (pdeath > get_rand_close_open(rng)) then
            ! Increase magnitude of nkill...
            nkill = nkill + 1
        end if

        ! The excitor might be a composite cluster so we'll just create
        ! excips in the spawned list and allow the annihilation process to take
        ! care of the rest.
        ! Pass through a null excitation so that we create a spawned particle on
        ! the current excitor.
        if (nkill /= 0) then
            ! Create nkill excips with sign of -K_ii A_i
            if (KiiAi > 0) nkill = -nkill
            call create_spawned_particle_truncated(cdet, null_excit, nkill, spawned_pop)
        end if

    end subroutine stochastic_ccmc_death

    pure subroutine collapse_cluster(excitor, excitor_population, cluster_excitor, cluster_population, allowed)

        ! Collapse two excitors.  The result is returned in-place.

        ! In:
        !    excitor: bit string of the Slater determinant formed by applying
        !        the excitor, e1, to the reference determinant.
        !    excitor_population: number of excips on the excitor e1.
        ! In/Out:
        !    cluster_excitor: bit string of the Slater determinant formed by applying
        !        the excitor, e2, to the reference determinant.
        !    cluster_population: number of excips on the 'cluster' excitor, e2.
        ! Out:
        !    allowed: true if excitor e1 can be applied to excitor e2 (i.e. e1
        !    and e2 do not involve exciting from/to the any identical
        !    spin-orbitals).

        ! On input, cluster excitor refers to an existing excitor, e2.  On output,
        ! cluster excitor refers to the excitor formed from applying the excitor
        ! e1 to the cluster e2.
        ! ***WARNING***: if allowed is false then cluster_excitor and
        ! cluster_population are *not* updated.

        use basis, only: basis_length, basis_lookup
        use excitations, only: excit_mask
        use fciqmc_data, only: f0

        use bit_utils, only: count_set_bits
        use const, only: i0_end

        integer(i0), intent(in) :: excitor(basis_length)
        integer, intent(in) :: excitor_population
        integer(i0), intent(inout) :: cluster_excitor(basis_length)
        real(p), intent(inout) :: cluster_population
        logical,  intent(out) :: allowed

        integer :: ibasis, ibit
        integer(i0) :: excitor_excitation(basis_length), excitor_annihilation(basis_length), excitor_creation(basis_length)
        integer(i0) :: cluster_excitation(basis_length), cluster_annihilation(basis_length), cluster_creation(basis_length)
        integer(i0) :: permute_operators(basis_length)

        ! Apply excitor to the cluster of excitors.

        ! orbitals involved in excitation from reference
        excitor_excitation = ieor(f0, excitor)
        cluster_excitation = ieor(f0, cluster_excitor)
        ! annihilation operators (relative to the reference)
        excitor_annihilation = iand(excitor_excitation, f0)
        cluster_annihilation = iand(cluster_excitation, f0)
        ! creation operators (relative to the reference)
        excitor_creation = iand(excitor_excitation, excitor)
        cluster_creation = iand(cluster_excitation, cluster_excitor)

        ! First, let's find out if the excitor is valid...
        if (any(iand(excitor_creation,cluster_creation) /= 0) &
                .or. any(iand(excitor_annihilation,cluster_annihilation) /= 0)) then
            ! excitor attempts to excite from an orbital already excited from by
            ! the cluster or into an orbital already excited into by the
            ! cluster.
            ! => not valid
            allowed = .false.
        else
            ! Applying the excitor to the existing cluster of excitors results
            ! in a valid cluster.
            allowed = .true.

            ! Combine amplitudes.
            ! Might need a sign change as well...see below!
            cluster_population = cluster_population*excitor_population

            ! Now apply the excitor to the cluster (which is, in its own right,
            ! an excitor).
            ! Consider a cluster, e.g. t_i^a = a^+_a a_i (which corresponds to i->a).
            ! We wish to collapse two excitors, e.g. t_i^a t_j^b, to a single
            ! excitor, e.g. t_{ij}^{ab} = a^+_a a^+_b a_j a_i (where i<j and
            ! a<b).  However t_i^a t_j^b = a^+_a a_i a^+_b a_j.  We thus need to
            ! permute the creation and annihilation operators.  Each permutation
            ! incurs a sign change.

            do ibasis = 1, basis_length
                do ibit = 0, i0_end
                    if (btest(excitor_excitation(ibasis),ibit)) then
                        if (btest(f0(ibasis),ibit)) then
                            ! Exciting from this orbital.
                            cluster_excitor(ibasis) = ibclr(cluster_excitor(ibasis),ibit)
                            ! We need to swap it with every annihilation
                            ! operator and every creation operator referring to
                            ! an orbital with a higher index already in the
                            ! cluster.
                            ! Note that an orbital cannot be in the list of
                            ! annihilation operators and the list of creation
                            ! operators.
                            ! First annihilation operators:
                            permute_operators = iand(excit_mask(:,basis_lookup(ibit,ibasis)),cluster_annihilation)
                            ! Now add the creation operators:
                            permute_operators = ior(permute_operators,cluster_creation)
                        else
                            ! Exciting into this orbital.
                            cluster_excitor(ibasis) = ibset(cluster_excitor(ibasis),ibit)
                            ! Need to swap it with every creation operator with
                            ! a lower index already in the cluster.
                            permute_operators = iand(not(excit_mask(:,basis_lookup(ibit,ibasis))),cluster_creation)
                            permute_operators(ibasis) = ibclr(permute_operators(ibasis),ibit)
                        end if
                        if (mod(sum(count_set_bits(permute_operators)),2) == 1) &
                            cluster_population = -cluster_population
                    end if
                end do
            end do

        end if

    end subroutine collapse_cluster

    subroutine convert_excitor_to_determinant(excitor, excitor_level, excitor_sign)

        ! We usually consider an excitor as a bit string representation of the
        ! determinant formed by applying the excitor (a group of annihilation
        ! and creation operators) to the reference determinant; indeed the
        ! determinant form is required when constructing Hamiltonian matrix
        ! elements.  However, the resulting determinant might actually contain
        ! a sign change, which needs to be absorbed into the (signed) population
        ! of excips on the excitor.

        ! This results from the fact that a determinant, |D>, is defined as:
        !   |D> = a^+_i a^+_j ... a^+_k |0>,
        ! where |0> is the vacuum, a^+_i creates an electron in the i-th
        ! orbital, i<j<...<k and |0> is the vacuum.  An excitor is defined as
        !   t_{ij...k}^{ab...c} = a^+_a a^+_b ... a^+_c a_k ... a_j a_i
        ! where i<j<...<k and a<b<...<c.  (This definition is somewhat
        ! arbitrary; the key thing is to be consistent.)  Hence applying an
        ! excitor to the reference might result in a change of sign, i.e.
        ! t_{ij}^{ab} |D_0> = -|D_{ij}^{ab}>.  As a more concrete example,
        ! consider a set of spin states (as the extension to fermions is
        ! irrelevant to the argument), with the reference:
        !   |D_0> = | 1 2 3 >
        ! and the excitor
        !   t_{13}^{58}
        ! Thus, using |0> to denote the vacuum:
        !   t_{13}^{58} | 1 2 3 > = + a^+_5 a^+_8 a_3 a_1 a^+_1 a^+_2 a^+_3 |0>
        !                         = + a^+_5 a^+_8 a_3 a^+_2 a^+_3 |0>
        !                         = - a^+_5 a^+_8 a_3 a^+_3 a^+_2 |0>
        !                         = - a^+_5 a^+_8 a^+_2 |0>
        !                         = + a^+_5 a^+_2 a^+_8 |0>
        !                         = - a^+_2 a^+_5 a^+_8 |0>
        !                         = - | 2 5 8 >
        ! Similarly
        !   t_{12}^{58} | 1 2 3 > = + a^+_5 a^+_8 a_2 a_1 a^+_1 a^+_2 a^+_3 |0>
        !                         = + a^+_5 a^+_8 a_2 a^+_2 a^+_3 |0>
        !                         = + a^+_5 a^+_8 a^+_3 |0>
        !                         = - a^+_5 a^+_3 a^+_8 |0>
        !                         = + a^+_3 a^+_5 a^+_8 |0>
        !                         = + | 3 5 8 >

        ! This potential sign change must be taken into account; we do so by
        ! absorbing the sign into the signed population of excips on the
        ! excitor.

        ! Essentially taken from Alex Thom's original implementation.

        ! In:
        !    excitor: bit string of the Slater determinant formed by applying
        !        the excitor to the reference determinant.
        !    excitor_level: excitation level, relative to the reference
        !        determinant, of the excitor.  Equal to the number of
        !        annihilation (or indeed creation) operators in the excitor.
        ! Out:
        !    excitor_sign: sign due to applying the excitor to the reference
        !    determinant to form a Slater determinant, i.e. < D_i | a_i D_0 >,
        !    which is +1 or -1, where D_i is the determinant formed from
        !    applying the cluster of excitors, a_i, to the reference
        !    determinant.

        use basis, only: basis_length
        use const, only: i0_end
        use fciqmc_data, only: f0

        integer(i0), intent(in) :: excitor(basis_length)
        integer, intent(in) :: excitor_level
        integer, intent(inout) :: excitor_sign

        integer(i0) :: excitation(basis_length)
        integer :: ibasis, ibit, ncreation, nannihilation

        ! Bits involved in the excitation from the reference determinant.
        excitation = ieor(f0, excitor)

        nannihilation = excitor_level
        ncreation = excitor_level

        excitor_sign = 1

        ! Obtain sign change by (implicitly) constructing the determinant formed
        ! by applying the excitor to the reference determinant.
        do ibasis = 1, basis_length
            do ibit = 0, i0_end
                if (btest(f0(ibasis),ibit)) then
                    ! Occupied orbital in reference.
                    if (btest(excitation(ibasis),ibit)) then
                        ! Orbital excited from...annihilate electron.
                        ! This amounts to one fewer operator in the cluster through
                        ! which the other creation operators in the determinant must
                        ! permute.
                        nannihilation = nannihilation - 1
                    else
                        ! Orbital is occupied in the reference and once the
                        ! excitor has been applied.
                        ! Permute the corresponding creation operator through
                        ! the remaining creation and annihilation operators of
                        ! the excitor (which operate on orbitals with a higher
                        ! index than the current orbital).
                        ! If the permutation is odd, then we incur a sign
                        ! change.
                        if (mod(nannihilation+ncreation,2) == 1) &
                            excitor_sign = -excitor_sign
                    end if
                else if (btest(excitation(ibasis),ibit)) then
                    ! Orbital excited to...create electron.
                    ! This amounts to one fewer operator in the cluster through
                    ! which the creation operators in the determinant must
                    ! permute.
                    ! Note due to definition of the excitor, it is guaranteed
                    ! that this is created in the correct place, ie there are no
                    ! other operators in the excitor it needs to be interchanged
                    ! with.
                    ncreation = ncreation - 1
                end if
            end do
        end do

    end subroutine convert_excitor_to_determinant

end module ccmc