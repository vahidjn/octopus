!! Copyright (C) 2010 X. Andrade
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
!! $Id: opencl_inc.F90 3587 2007-11-22 16:43:00Z xavier $


subroutine X(opencl_write_buffer)(this, size, data, offset)
  type(opencl_mem_t),               intent(inout) :: this
  integer,                          intent(in)    :: size
  R_TYPE,                           intent(in)    :: data(:)
  integer,                optional, intent(in)    :: offset

  integer(SIZEOF_SIZE_T) :: fsize, offset_
  integer :: ierr

  call profiling_in(prof_write, "CL_WRITE_BUFFER")

  fsize = size*R_SIZEOF
  offset_ = 0
  if(present(offset)) offset_ = offset*R_SIZEOF

  call flEnqueueWriteBuffer(this%mem, opencl%command_queue, fsize, offset_, data(1), ierr)

  if(ierr /= CL_SUCCESS) call opencl_print_error(ierr, "EnqueueWriteBuffer")

  call profiling_count_transfers(size, data(1))
  call opencl_finish()
  call profiling_out(prof_write)

end subroutine X(opencl_write_buffer)

! -----------------------------------------------------------------------------

subroutine X(opencl_write_buffer_2)(this, size, data, offset)
  type(opencl_mem_t),               intent(inout) :: this
  integer,                          intent(in)    :: size
  R_TYPE,                           intent(in)    :: data(:, :)
  integer,                optional, intent(in)    :: offset

  integer(SIZEOF_SIZE_T) :: fsize, offset_
  integer :: ierr

  call profiling_in(prof_write, "CL_WRITE_BUFFER")

  fsize = size*R_SIZEOF
  offset_ = 0
  if(present(offset)) offset_ = offset*R_SIZEOF

  call flEnqueueWriteBuffer(this%mem, opencl%command_queue, fsize, offset_, data(1, 1), ierr)

  if(ierr /= CL_SUCCESS) call opencl_print_error(ierr, "EnqueueWriteBuffer")

  call profiling_count_transfers(size, data(1, 1))
  call opencl_finish()
  call profiling_out(prof_write)

end subroutine X(opencl_write_buffer_2)

! -----------------------------------------------------------------------------

subroutine X(opencl_read_buffer)(this, size, data, offset)
  type(opencl_mem_t),               intent(inout) :: this
  integer,                          intent(in)    :: size
  R_TYPE,                           intent(out)   :: data(:)
  integer,                optional, intent(in)    :: offset

  integer(SIZEOF_SIZE_T) :: fsize, offset_
  integer :: ierr

  call profiling_in(prof_read, "CL_READ_BUFFER")

  fsize = size*R_SIZEOF
  offset_ = 0
  if(present(offset)) offset_ = offset*R_SIZEOF

  call flEnqueueReadBuffer(this%mem, opencl%command_queue, fsize, offset_, data(1), ierr)
  if(ierr /= CL_SUCCESS) call opencl_print_error(ierr, "EnqueueReadBuffer")

  call profiling_count_transfers(size, data(1))
  call opencl_finish()
  call profiling_out(prof_read)

end subroutine X(opencl_read_buffer)

! ---------------------------------------------------------------------------

subroutine X(opencl_read_buffer_2)(this, size, data, offset)
  type(opencl_mem_t),               intent(inout) :: this
  integer,                          intent(in)    :: size
  R_TYPE,                           intent(out)   :: data(:, :)
  integer,                optional, intent(in)    :: offset

  integer(SIZEOF_SIZE_T) :: fsize, offset_
  integer :: ierr
  
  call profiling_in(prof_read, "CL_READ_BUFFER")

  fsize = size*R_SIZEOF
  offset_ = 0
  if(present(offset)) offset_ = offset*R_SIZEOF

  call flEnqueueReadBuffer(this%mem, opencl%command_queue, fsize, offset_, data(1, 1), ierr)
  if(ierr /= CL_SUCCESS) call opencl_print_error(ierr, "EnqueueReadBuffer")

  call profiling_count_transfers(size, data(1, 1))
  call opencl_finish()
  call profiling_out(prof_read)
  
end subroutine X(opencl_read_buffer_2)

! ---------------------------------------------------------------------------

subroutine X(opencl_set_kernel_arg_data)(kernel, narg, data)
  type(c_ptr),        intent(inout) :: kernel
  integer,            intent(in)    :: narg
  R_TYPE,             intent(in)    :: data
  
  integer :: ierr

  call f90_cl_set_kernel_arg_data(kernel, narg, R_SIZEOF, data, ierr)
  if(ierr /= CL_SUCCESS) call opencl_print_error(ierr, "set_kernel_arg_data")

end subroutine X(opencl_set_kernel_arg_data)

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
