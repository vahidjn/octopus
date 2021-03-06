!! Copyright (C) 2002-2006 M. Marques, A. Castro, A. Rubio, G. Bertsch
!!
!! This program is free software; you can redistribute it and/or modify
!! it under the terms of the GNU General Public License as published by
!! the Free Software Foundation; either version 2, or (at your option)
!! any later version.
!!
!! This program is distributed in the hope that it will be useful,
!! but WITHOUT ANY WARRANTY; without even the implied warranty of
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!! GNU General Public License for more details.
!!
!! You should have received a copy of the GNU General Public License
!! along with this program; if not, write to the Free Software
!! Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
!! 02111-1307, USA.
!!
!! $Id: ground_state.F90 8250 2011-09-02 02:51:51Z dstrubbe $

#include "global.h"

module ground_state_m
  use calc_mode_m
  use datasets_m
  use energy_m
  use global_m
  use grid_m
  use hamiltonian_m
  use lcao_m
  use mesh_m
  use messages_m
  use mpi_m
  use multicomm_m
  use parser_m
  use restart_m
  use scf_m
  use simul_box_m
  use species_m
  use species_pot_m
  use states_m
  use states_calc_m
  use states_io_m
  use system_m
  use v_ks_m
  use varinfo_m

  implicit none

  private
  public ::                 &
    ground_state_run_init,  &
    ground_state_run


contains

  subroutine ground_state_run_init()

    call calc_mode_set_parallelization(P_STRATEGY_STATES, default = .false.)
    call calc_mode_set_scalapack_compat()

  end subroutine ground_state_run_init

  ! ---------------------------------------------------------
  subroutine ground_state_run(sys, hm, fromScratch)
    type(system_t),      intent(inout) :: sys
    type(hamiltonian_t), intent(inout) :: hm
    logical,             intent(inout) :: fromScratch

    type(scf_t)  :: scfv
    integer      :: ierr

    PUSH_SUB(ground_state_run)

    message(1) = "Info: Allocating ground state wave-functions"
    call messages_info(1)

    call states_allocate_wfns(sys%st, sys%gr%mesh)
#ifdef HAVE_MPI
    ! sometimes a deadlock can occur here (if some nodes can allocate and other cannot)
    call MPI_Barrier(sys%st%dom_st_kpt_mpi_grp%comm, mpi_err)
#endif
    message(1) = "      done."
    call messages_info(1)

    ! Read free states for ground-state open-boundary calculation.
    if(sys%gr%ob_grid%open_boundaries) then
      call states_allocate_free_states(sys%st, sys%gr)
      call read_free_states(sys%st, sys%gr)
      ! allocate self_energy and calculate
      call states_init_self_energy(sys%st, sys%gr, hm%d%nspin, hm%d%ispin, hm%lead)
    end if

    if(.not. fromScratch) then
      ! load wavefunctions
      call restart_read(trim(restart_dir)//GS_DIR, sys%st, sys%gr, sys%geo, ierr, read_occ = .not. sys%st%fixed_occ)
      if(ierr .ne. 0) then
        message(1) = "Could not load wavefunctions from '"//trim(restart_dir)//GS_DIR//"'"
        message(2) = "Starting from scratch!"
        call messages_warning(2)
        fromScratch = .true.
      end if
    end if

    if(fromScratch) then
      call lcao_run(sys, hm)
    else
      ! setup Hamiltonian
      message(1) = 'Info: Setting up Hamiltonian.'
      call messages_info(1)
      call system_h_setup(sys, hm)
    end if

    ! run self-consistency
    if (states_are_real(sys%st)) then
      message(1) = 'Info: SCF using real wavefunctions.'
    else
      message(1) = 'Info: SCF using complex wavefunctions.'
    end if
    call messages_info(1)

    call scf_init(scfv, sys%gr, sys%geo, sys%st, hm)
    call scf_run(scfv, sys%gr, sys%geo, sys%st, sys%ks, hm, sys%outp)
    call scf_end(scfv)

    ! clean up
    call states_deallocate_wfns(sys%st)
    call states_deallocate_free_states(sys%st, sys%gr)

    POP_SUB(ground_state_run)
  end subroutine ground_state_run

end module ground_state_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
