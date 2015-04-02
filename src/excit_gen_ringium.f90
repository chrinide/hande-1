module excit_gen_ringium

use const

implicit none

contains

    subroutine gen_excit_ringium_no_renorm(rng, sys, qmc_in, cdet, pgen, connection, hmatel)

        ! Create a random excitation from cdet and calculate the probability of
        ! selecting that excitation.

        ! In:
        !    sys: system object being studied.
        !    qmc_in: input options relating to QMC methods
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        ! Out:
        ! In/Out:
        !    rng: random number generator.
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant 

        use determinants, only: det_info_t
        use excitations, only: excit_t, find_excitation_permutation2
        use system, only: sys_t
        use hamiltonian_ringium, only: slater_condon2_ringium
        use dSFMT_interface, only: dSFMT_t
        use qmc_data, only: qmc_in_t

        type(sys_t), intent(in) :: sys
        type(det_info_t), intent(in) :: cdet
        type(qmc_in_t), intent(in) :: qmc_in
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen, hmatel
        type(excit_t), intent(out) :: connection

        logical :: allowed
        integer :: ij_lz

        connection%nexcit = 2
        ! 1. Select a random pair of spin orbitals to excite from.
        call choose_ij_ringium(rng, sys, cdet%occ_list, connection%from_orb(1), connection%from_orb(2), ij_lz)

        ! 2. Select a random pair of spin orbitals to excite to.
        call choose_ab_ringium(rng, sys, cdet%f, ij_lz, connection%to_orb(1), connection%to_orb(2), allowed)

        if (allowed) then
            ! 3. Calculate the generation probability of the excitation.
            ! For one-band systems this depends only upon the orbitals excited from.
            pgen = calc_pgen_ringium(sys)

            call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

            ! 4. find the connecting matrix element.
            hmatel = slater_condon2_ringium(sys, connection%from_orb(1), connection%from_orb(2), &
                        connection%to_orb(1), connection%to_orb(2), connection%perm)
        else
            pgen = 1.0_p
            hmatel = 0.0_p
        end if

    end subroutine gen_excit_ringium_no_renorm

    subroutine choose_ij_ringium(rng, sys, occ_list, i, j, ij_lz)
      
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use system, only: sys_t

        type(dSFMT_t), intent(inout) :: rng
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: occ_list(:)
        integer, intent(out) :: i, j, ij_lz

        real(dp) :: r
        integer :: ind

        r = get_rand_close_open(rng)
        ind = int(r*sys%nel*(sys%nel-1)/2) + 1
        ! Indices in list of occupied spin-orbitals
        j = int(1.50_p + sqrt(2*ind-1.750_p))
        i = ind - ((j-1)*(j-2))/2
        ! Corresponding spin orbitals
        i = occ_list(i)
        j = occ_list(j)
        ij_lz = sys%basis%basis_fns(i)%l(1) + sys%basis%basis_fns(j)%l(1)

    end subroutine choose_ij_ringium

    subroutine choose_ab_ringium(rng, sys, f, ij_lz, a, b, allowed)

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use system, only: sys_t

        type(dSFMT_t), intent(inout) :: rng
        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f(sys%basis%string_len)
        integer, intent(in) :: ij_lz
        integer, intent(out) :: a, b
        logical, intent(out) :: allowed

        integer :: lz_b, ind

        ! Select a random unoccupied orbital as a
        do
            a = 2 * int(get_rand_close_open(rng)*sys%basis%nbasis/2) + 1
            ! If a is unoccupied, then found orbital to excite to
            if (.not.btest(f(sys%basis%bit_lookup(2,a)), sys%basis%bit_lookup(1,a))) exit
        end do

        lz_b = ij_lz - sys%basis%basis_fns(a)%l(1)

        if (abs(lz_b) > sys%ringium%maxlz) then
            allowed = .false.
        else
            ! The basis function lz = k is 2k+1 for k>=0 or 2k-1 for k<0
            b = 2*abs(lz_b)
            if (lz_b >= 0) then
                b = b + 1
            else
                b = b -1
            end if
            ! Allowed if b is unoccupied (and not a)
            allowed = .not.btest(f(sys%basis%bit_lookup(2,b)), sys%basis%bit_lookup(1,b))
            if (a == b) allowed = .false.
        end if
        ! Ensure a < b (as assumed by other procedures)
        if (a > b) then
            ind = a
            a = b
            b = ind
        end if

    end subroutine choose_ab_ringium

    pure function calc_pgen_ringium(sys) result(pgen)

        use system, only: sys_t

        type(sys_t), intent(in) :: sys
        real(p) :: pgen

        ! i and j are chosen uniformly from the nel*(nel-1)/2 possible pairs
        ! a is chosen randomly from the nspatial - nel unoccupied orbitals
        ! b is then fixed
        ! a and b could have been chosen in either order so
        ! p_gen = p(a|i,j) p(b|i,j,a) + p(b|i,j) p(a|i,j,b)
        !       = 4/(nel*(nel-1)*(nbasis/2-nel))

        pgen = 4.0/(sys%nel*(sys%nel-1)*(sys%basis%nbasis/2-sys%nel))

    end function calc_pgen_ringium

end module excit_gen_ringium
