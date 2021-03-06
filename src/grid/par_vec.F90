!! Copyright (C) 2005-2006 Florian Lorenzen, Heiko Appel
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
!! $Id: par_vec.F90 7642 2011-03-29 19:05:15Z dstrubbe $

#include "global.h"

  !> Some general things and nomenclature:
  !!
  !! - Points that are stored only on one node are
  !!   called local points.
  !! - Local points that are stored redundantly on
  !!   another node because of the partitioning are
  !!   called ghost points.
  !! - Points from the enlargement are only stored
  !!   once on the corresponding node and are called
  !!   boundary points.
  !! - np is the total number of inner points.
  !!
  !! A globally defined vector v has two parts:
  !! - v(1:np) are the inner points
  !! - v(np+1:np_part) are the boundary points
  !! In the typical case of zero boundary conditions
  !! v(np+1:np_part) is 0.
  !! The two parts are split according to the partitions.
  !! The result of this split are local vectors vl on each node
  !! which consist of three parts:
  !! - vl(1:np_local)                                     local points.
  !! - vl(np_local+1:np_local+np_ghost)                   ghost points.
  !! - vl(np_local+np_ghost+1:np_local+np_ghost+np_bndry) boundary points.
  !!
  !!
  !! Usage example for par_vec routines.
  !!
  !! ! Initialize parallelization with mesh and operator op
  !! ! initialized and given.
  !! ! mesh       = sys%gr%mesh
  !! ! stencil    = op%stencil
  !!
  !! FLOAT              :: uu(np_global), vv(np_global)
  !! FLOAT, allocatable :: ul(:), vl(:), wl(:)
  !! type(mesh_t)       :: mesh
  !!
  !! ! Fill uu, vv with sensible values.
  !! ! ...
  !!
  !! ! Allocate space for local vectors.
  !! allocate(ul(np_part))
  !! allocate(vl(np_part))
  !! allocate(wl(np_part))
  !!
  !! ! Distribute vectors.
  !! call X(vec_scatter)(vp, uu, ul)
  !! call X(vec_scatter)(vp, vv, vl)
  !!
  !! ! Compute some operator op: vl = op ul
  !! call X(vec_ghost_update)(vp, ul)
  !! call X(nl_operator_operate)(op, ul, vl)
  !! !! Gather result of op in one vector vv.
  !! call X(vec_gather)(vp, vv, vl)
  !!
  !! ! Clean up.
  !! deallocate(ul, vl, wl)

module par_vec_m
  use global_m
  use iihash_m
  use index_m
  use io_m
  use messages_m
  use mpi_m
  use mpi_debug_m
  use profiling_m
  use stencil_m
  use subarray_m

  implicit none

  private

  public ::                        &
    pv_t

#if defined(HAVE_MPI)
  public ::                        &
    vec_init,                      &
    vec_end,                       &
    vec_global2local,              &
    dvec_scatter,                  &
    zvec_scatter,                  &
    ivec_scatter,                  &
    dvec_scatter_bndry,            &
    zvec_scatter_bndry,            &
    ivec_scatter_bndry,            &
    dvec_scatter_all,              &
    zvec_scatter_all,              &
    ivec_scatter_all,              &
    dvec_gather,                   &
    zvec_gather,                   &
    ivec_gather,                   &
    dvec_selective_gather,         &
    zvec_selective_gather,         &
    dvec_selective_scatter,        &
    zvec_selective_scatter,        &
    dvec_allgather,                &
    zvec_allgather,                &
    ivec_allgather
#endif

  type pv_t
    ! The content of these members is node-dependent.
    integer          :: rank                 !< Our rank in the communicator.
    integer          :: partno               !< Partition number of the
                                             !< current node
    type(subarray_t) :: sendpoints
    integer, pointer :: sendpos(:)

    integer, pointer :: rdispls(:)
    integer, pointer :: sdispls(:)
    integer, pointer :: rcounts(:)

    ! The following members are set independent of the nodes.
    integer                 :: npart                !< Number of partitions.
    integer                 :: root                 !< The master node.
    integer                 :: comm                 !< MPI communicator to use.
    integer                 :: np                   !< Number of points in mesh.
    integer                 :: np_enl               !< Number of points in enlargement.
    integer, pointer        :: part(:)              !< Point -> partition.
    integer, pointer        :: np_local(:)          !< How many points has partition r?
    integer, pointer        :: xlocal(:)            !< Points of partition r start at
                                                    !< xlocal(r) in local.
    integer, pointer        :: local(:)             !< Partition r has points
                                                    !< local(xlocal(r):
                                                    !< xlocal(r)+np_local(r)-1).
    integer, pointer        :: np_bndry(:)          !< Number of boundary points.
    integer, pointer        :: xbndry(:)            !< Index of bndry(:).
    integer, pointer        :: bndry(:)             !< Global numbers of boundary
                                                    !< points.
    type(iihash_t), pointer :: global(:)            !< global(r) contains the global ->
                                                    !< local mapping for partition r.
    integer                 :: total                !< Total number of ghost points.
    integer, pointer        :: np_ghost(:)          !< How many ghost points has
                                                    !< partition r?
    integer, pointer        :: np_ghost_neigh(:, :) !< Number of ghost points per
                                                    !< neighbour per partition.
    integer, pointer        :: xghost(:)            !< Like xlocal.
    integer, pointer        :: xghost_neigh(:, :)   !< Like xghost for neighbours.
    integer, pointer        :: ghost(:)             !< Global indices of all local
  end type pv_t

#if defined(HAVE_MPI)

  type(profile_t), save :: prof_scatter
  type(profile_t), save :: prof_allgather

contains

  !> Initializes a pv_type object (parallel vector).
  !! It computes the local-to-global and global-to-local index tables
  !! and the ghost point exchange.
  !!
  !! Note: we cannot pass in the i(:, :) array from the stencil
  !! because it is not yet computed (it is local to a node and
  !! must be initialized some time after vec_init is run).
  !! \warning The naming scheme for the np_ variables is different
  !! from how it is in the rest of the code (for historical reasons
  !! and also because the vec_init has more a global than local point
  !! of view on the mesh): See the comments in the parameter list.
  subroutine vec_init(comm, root, part, np, np_part, idx, stencil, dim, vp)
    integer,         intent(in)  :: comm         !< Communicator to use.
    integer,         intent(in)  :: root         !< The master node.

    ! The next seven entries come from the mesh.
    integer,         intent(in)  :: part(:)      !< Point -> partition.
    integer,         intent(in)  :: np           !< mesh%np_global
    integer,         intent(in)  :: np_part      !< mesh%np_part_global
    type(index_t),   intent(in)  :: idx
    type(stencil_t), intent(in)  :: stencil      !< The stencil for which to calculate ghost points.
    integer,         intent(in)  :: dim          !< Number of dimensions.
    type(pv_t),      intent(out) :: vp           !< Description of partition.

    ! Careful: MPI counts node ranks from 0 to numproc-1.
    ! Partition numbers from METIS range from 1 to numproc.
    ! For this reason, all ranks are incremented by one.
    integer                     :: npart            !< Number of partitions.
    integer                     :: np_enl           !< Number of points in enlargement.
    integer                     :: ip, jp, jj, index, inode, jnode !< Counters.
    integer, allocatable        :: ir(:), irr(:, :) !< Counters.
    integer                     :: rank             !< Rank of current node.
    integer                     :: p1(MAX_DIM)      !< Points.
    type(iihash_t), allocatable :: ghost_flag(:)    !< To remember ghost pnts.
    integer                     :: iunit            !< For debug output to files.
    character(len=3)            :: filenum
    integer                     :: tmp
    logical                     :: found

    PUSH_SUB(vec_init)

    ! Shortcuts.
    call MPI_Comm_Size(comm, npart, mpi_err)
    np_enl = np_part - np

    ! Store partition number and rank for later reference.
    ! Having both variables is a bit redundant but makes the code readable.
    call MPI_Comm_Rank(comm, rank, mpi_err)
    vp%rank   = rank
    vp%partno = rank + 1

    SAFE_ALLOCATE(ghost_flag(1:npart))
    SAFE_ALLOCATE(ir(1:npart))
    SAFE_ALLOCATE(irr(1:npart, 1:npart))
    SAFE_ALLOCATE(vp%part(1:np+np_enl))
    SAFE_ALLOCATE(vp%np_local(1:npart))
    SAFE_ALLOCATE(vp%xlocal(1:npart))
    SAFE_ALLOCATE(vp%local(1:np))
    SAFE_ALLOCATE(vp%np_bndry(1:npart))
    SAFE_ALLOCATE(vp%xbndry(1:npart))
    SAFE_ALLOCATE(vp%bndry(1:np_enl))
    SAFE_ALLOCATE(vp%global(1:npart))
    SAFE_ALLOCATE(vp%np_ghost(1:npart))
    SAFE_ALLOCATE(vp%np_ghost_neigh(1:npart, 1:npart))
    SAFE_ALLOCATE(vp%xghost(1:npart))
    SAFE_ALLOCATE(vp%xghost_neigh(1:npart, 1:npart))

    ! Count number of points for each node.
    ! Local points.
    vp%np_local = 0
    do ip = 1, np
      vp%np_local(part(ip)) = vp%np_local(part(ip)) + 1
    end do
    ! Boundary points.
    vp%np_bndry = 0
    do ip = 1, np_enl
      vp%np_bndry(part(ip + np)) = vp%np_bndry(part(ip + np)) + 1
    end do

    ! Set up local-to-global index table for local points
    ! (xlocal, local) and for boundary points (xbndry, bndry).
    vp%xlocal(1) = 1
    vp%xbndry(1) = 1
    do inode = 2, npart
      vp%xlocal(inode) = vp%xlocal(inode - 1) + vp%np_local(inode - 1)
      vp%xbndry(inode) = vp%xbndry(inode - 1) + vp%np_bndry(inode - 1)
    end do
    ir = 0
    do ip = 1, np
      vp%local(vp%xlocal(part(ip)) + ir(part(ip))) = ip
      ir(part(ip))                                 = ir(part(ip)) + 1
    end do
    ir = 0
    do ip = np+1, np+np_enl
      vp%bndry(vp%xbndry(part(ip)) + ir(part(ip))) = ip
      ir(part(ip))                                 = ir(part(ip)) + 1
    end do

    ! Format of ghost:
    !
    ! np_ghost_neigh, np_ghost, xghost_neigh, xghost are components of vp.
    ! The vp% is omitted due to space constraints.
    !
    ! The following figure shows how ghost points of node "inode" are put into ghost:
    !
    !  |<-------------------------------------------np_ghost(inode)--------------------------------------->|
    !  |                                                                                                   |
    !  |<-np_ghost_neigh(inode,1)->|     |<-np_ghost_neigh(inode,npart-1)->|<-np_ghost_neigh(inode,npart)->|
    !  |                           |     |                                 |                               |
    ! -------------------------------------------------------------------------------------------------------
    !  |                           | ... |                                 |                               |
    ! -------------------------------------------------------------------------------------------------------
    !  ^                                 ^                                 ^
    !  |                                 |                                 |
    !  xghost_neigh(inode,1)             xghost_neigh(inode,npart-1)       xghost_neigh(inode,npart)
    !  |
    !  xghost(inode)

    ! Mark and count ghost points and neighbours
    ! (set vp%np_ghost_neigh, vp%np_ghost, ghost_flag).
    do inode = 1, npart
      call iihash_init(ghost_flag(inode), vp%np_local(inode))
    end do

    do jj = 1, stencil%size
      ASSERT(all(stencil%points(1:dim, jj) <= idx%enlarge(1:dim)))
    end do

    vp%total          = 0
    vp%np_ghost_neigh = 0
    vp%np_ghost       = 0
    ! Check all nodes.
    do inode = 1, npart
      ! Check all points of this node.
      do ip = vp%xlocal(inode), vp%xlocal(inode)+ vp%np_local(inode) - 1
        ! Get coordinates of current point.
        call index_to_coords(idx, dim, vp%local(ip), p1)

        ! For all points in stencil.
        do jj = 1, stencil%size
          ! Get point number of possible ghost point.
          index = index_from_coords(idx, dim, p1(:) + stencil%points(:, jj))
          ASSERT(index.ne.0)
          ! If this index does not belong to partition of node "inode",
          ! then index is a ghost point for "inode" with part(index) now being
          ! a neighbour of "inode".
          if(part(index).ne.inode) then
            ! Only mark and count this ghost point, if it is not
            ! done yet. Otherwise, points would possibly be registered
            ! more than once.
            tmp = iihash_lookup(ghost_flag(inode), index, found)
            if(.not.found) then
              ! Mark point ip as ghost point for inode from part(index).
              call iihash_insert(ghost_flag(inode), index, part(index))
              ! Increase number of ghost points of inode from part(index).
              vp%np_ghost_neigh(inode, part(index)) = vp%np_ghost_neigh(inode, part(index))+1
              ! Increase total number of ghostpoints of inode.
              vp%np_ghost(inode)                    = vp%np_ghost(inode) + 1
              ! One more ghost point.
              vp%total                              = vp%total + 1
            end if
          end if
        end do
      end do
    end do

    ! Set index tables xghost and xghost_neigh.
    vp%xghost(1) = 1
    do inode = 2, npart
      vp%xghost(inode) = vp%xghost(inode - 1) + vp%np_ghost(inode - 1)
    end do
    do inode = 1, npart
      vp%xghost_neigh(inode, 1) = vp%xghost(inode)
      do jnode = 2, npart
        vp%xghost_neigh(inode, jnode) = vp%xghost_neigh(inode, jnode - 1) + vp%np_ghost_neigh(inode, jnode - 1)
      end do
    end do

    ! Get space for ghost point vector.
    SAFE_ALLOCATE(vp%ghost(1:vp%total))

    ! Fill ghost as described above.
    irr = 0
    do ip = 1, np+np_enl
      do inode = 1, npart
        jnode = iihash_lookup(ghost_flag(inode), ip, found)
        ! If point ip is a ghost point for inode from jnode, save this
        ! information.
        if(found) then
          vp%ghost(vp%xghost_neigh(inode, jnode) + irr(inode, jnode)) = ip
          irr(inode, jnode)                                           = irr(inode, jnode) + 1
        end if
      end do
    end do

    if(in_debug_mode) then
      ! Write numbers and coordinates of each nodes ghost points
      ! to a single file (like in mesh_partition_init) called
      ! debug/mesh_partition/ghost_points.###.
      if(mpi_grp_is_root(mpi_world)) then
        call io_mkdir('debug/mesh_partition')
        do inode = 1, npart
          write(filenum, '(i3.3)') inode
          iunit = io_open('debug/mesh_partition/ghost_points.'//filenum, &
            action='write')
          do ip = 1, vp%np_ghost(inode)
            jp = vp%ghost(vp%xghost(inode) + ip - 1)
            write(iunit, '(4i8)') jp, idx%lxyz(jp, :)
          end do
          call io_close(iunit)
        end do
      end if
    end if

    ! Set up the global-to-local point number mapping.
    do inode = 1, npart
      ! Create hash table.
      call iihash_init(vp%global(inode), vp%np_local(inode) + vp%np_ghost(inode) + vp%np_bndry(inode))
      ! Insert local points.
      do ip = 1, vp%np_local(inode)
        call iihash_insert(vp%global(inode), vp%local(vp%xlocal(inode) + ip - 1), ip)
      end do
      ! Insert ghost points.
      do ip = 1, vp%np_ghost(inode)
        call iihash_insert(vp%global(inode), vp%ghost(vp%xghost(inode) + ip - 1), ip + vp%np_local(inode))
      end do
      ! Insert boundary points.
      do ip = 1, vp%np_bndry(inode)
        call iihash_insert(vp%global(inode), vp%bndry(vp%xbndry(inode) + ip - 1), ip + vp%np_local(inode) + vp%np_ghost(inode))
      end do
    end do
    
    ! Complete entries in vp.
    vp%comm   = comm
    vp%root   = root
    vp%np     = np
    vp%np_enl = np_enl
    vp%npart  = npart
    vp%part   = part

    call init_send_points

    do inode = 1, npart
      call iihash_end(ghost_flag(inode))
    end do

    POP_SUB(vec_init)

  contains
    
    subroutine init_send_points
      integer, allocatable :: displacements(:)
      integer :: ii, jj, kk, ipart, total

      PUSH_SUB(vec_init.init_send_points)

      SAFE_ALLOCATE(vp%sendpos(1:vp%npart))

      total = sum(vp%np_ghost_neigh(1:vp%npart, vp%partno))

      SAFE_ALLOCATE(displacements(1:total))
        
      jj = 0
      ! Iterate over all possible receivers.
      do ipart = 1, vp%npart
        vp%sendpos(ipart) = jj + 1
        ! Iterate over all ghost points that ipart wants.
        do ii = 0, vp%np_ghost_neigh(ipart, vp%partno) - 1
          ! Get global number kk of i-th ghost point.
          kk = vp%ghost(vp%xghost_neigh(ipart, vp%partno) + ii)
          ! Lookup up local number of point kk
          jj = jj + 1
          displacements(jj) = vec_global2local(vp, kk, vp%partno)
        end do
      end do

      call subarray_init(vp%sendpoints, total, displacements)

      SAFE_DEALLOCATE_A(displacements)
        
      ! Send and receive displacements.
      ! Send displacement cannot directly be calculated
      ! from vp%xghost_neigh because those are indices for
      ! vp%np_ghost_neigh(vp%partno, :) and not
      ! vp%np_ghost_neigh(:, vp%partno) (rank being fixed).
      ! So what gets done is to pick out the number of ghost points
      ! each partition r wants to have from the current partiton
      ! vp%partno.
      
      SAFE_ALLOCATE(vp%sdispls(1:vp%npart))
      SAFE_ALLOCATE(vp%rdispls(1:vp%npart))
      SAFE_ALLOCATE(vp%rcounts(1:vp%npart))

      vp%sdispls(1) = 0
      do ipart = 2, vp%npart
        vp%sdispls(ipart) = vp%sdispls(ipart - 1) + vp%np_ghost_neigh(ipart - 1, vp%partno)
      end do

      ! This is like in vec_scatter/gather.
      vp%rdispls(1:vp%npart) = vp%xghost_neigh(vp%partno, 1:vp%npart) - vp%xghost(vp%partno)
      
      vp%rcounts(1:vp%npart) = vp%np_ghost_neigh(vp%partno, 1:vp%npart)

      POP_SUB(vec_init.init_send_points)
    end subroutine init_send_points

  end subroutine vec_init


  ! ---------------------------------------------------------
  !> Deallocate memory used by vp.
  subroutine vec_end(vp)
    type(pv_t), intent(inout) :: vp

    integer :: ipart

    PUSH_SUB(vec_end)

    call subarray_end(vp%sendpoints)

    SAFE_DEALLOCATE_P(vp%rdispls)
    SAFE_DEALLOCATE_P(vp%sdispls)
    SAFE_DEALLOCATE_P(vp%rcounts)
    SAFE_DEALLOCATE_P(vp%sendpos)
    SAFE_DEALLOCATE_P(vp%part)
    SAFE_DEALLOCATE_P(vp%np_local)
    SAFE_DEALLOCATE_P(vp%xlocal)
    SAFE_DEALLOCATE_P(vp%local)
    SAFE_DEALLOCATE_P(vp%np_bndry)
    SAFE_DEALLOCATE_P(vp%xbndry)
    SAFE_DEALLOCATE_P(vp%bndry)
    SAFE_DEALLOCATE_P(vp%np_ghost)
    SAFE_DEALLOCATE_P(vp%np_ghost_neigh)
    SAFE_DEALLOCATE_P(vp%xghost)
    SAFE_DEALLOCATE_P(vp%xghost_neigh)
    SAFE_DEALLOCATE_P(vp%ghost)

    if(associated(vp%global)) then
      do ipart = 1, vp%npart
        call iihash_end(vp%global(ipart))
      end do
      SAFE_DEALLOCATE_P(vp%global)
    end if

    POP_SUB(vec_end)

  end subroutine vec_end

  ! ---------------------------------------------------------
  !> Returns local number of global point ip on partition inode.
  !! If the result is zero, the point is neither a local nor a ghost
  !! point on inode.
  integer function vec_global2local(vp, ip, inode)
    type(pv_t), intent(in) :: vp
    integer,    intent(in) :: ip
    integer,    intent(in) :: inode

    integer :: nn
    logical :: found

! no push_sub because called too frequently

    vec_global2local = 0
    if(associated(vp%global)) then
      nn = iihash_lookup(vp%global(inode), ip, found)
      if(found) vec_global2local = nn
    end if

  end function vec_global2local

#include "undef.F90"
#include "complex.F90"
#include "par_vec_inc.F90"

#include "undef.F90"
#include "real.F90"
#include "par_vec_inc.F90"

#include "undef.F90"
#include "integer.F90"
#include "par_vec_inc.F90"

#endif
end module par_vec_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
