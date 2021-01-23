! written by jxzou at 20210115: generate Gaussian .gjf from ORCA .mkl file
! TODO: un-normalize the contracted coefficients of each basis function

! Note: this utility can only be applied to all-electron basis set, since the
!  .mkl file does not contain ECP information

! The 'Shell types' array in Gaussian .fch file:
!
!   Spherical     |   
! -5,-4,-3,-2,-1, 0, 1
!  H  G  F  D  L  S  P
!
! 'L' is 'SP' in Pople-type basis sets

program main
 implicit none
 integer :: i
 integer, parameter :: iout = 6
 character(len=3) :: str
 character(len=240) :: mklname
 logical :: print_mo

 i = iargc()
 if(i<1 .or. i>2) then
  write(iout,'(/,A)')  ' ERROR in subroutine mkl2gjf: wrong command line arguments.'
  write(iout,'(A)')    ' Example 1: mkl2gjf a.mkl     (coordinates and basis)'
  write(iout,'(A,/)')  ' Example 2: mkl2gjf a.mkl -mo (plus MOs)'
  stop
 end if

 mklname = ' '
 call getarg(1, mklname)
 call require_file_exist(mklname)

 str = ' '
 print_mo = .false.
 if(i == 2) then
  call getarg(2, str)
  if(str /= '-mo') then
   write(iout,'(A)')  'ERROR in subroutine mkl2gjf: wrong command line arguments.'
   write(iout,'(A)')  "The 2nd argument can only be '-mo'."
   stop
  end if
  print_mo = .true.
 end if

 call mkl2gjf(mklname, print_mo)
 stop
end program main

! generate Gaussian .gjf from ORCA .mkl file
! if print_mo = .True., print MOs into .gjf
subroutine mkl2gjf(mklname, print_mo)
 use mkl_content
 implicit none
 integer :: i, j, k, nc, nline, ncol, fid
 integer :: nf3mark, ng3mark, nh3mark
 integer, parameter :: iout = 6
 integer, allocatable :: f3_mark(:), g3_mark(:), h3_mark(:)
 character(len=240) :: buf, gjfname
 character(len=240), intent(in) :: mklname
 logical :: uhf
 logical, intent(in) :: print_mo

 i = INDEX(mklname,'.',back=.true.)
 if(i == 0) then
  write(iout,'(A)') "ERROR in subroutine mkl2gjf: input filename does not&
                   & contain '.' key!"
  write(iout,'(A)') 'mklname='//TRIM(mklname)
  stop
 end if
 gjfname = mklname(1:i-1)//'.gjf'

 open(newunit=fid,file=TRIM(gjfname),status='replace')
 write(fid,'(A)') '%chk='//mklname(1:i-1)//'.chk'
 write(fid,'(A)') '%nprocshared=4'
 write(fid,'(A)') '%mem=4GB'

 call check_uhf_in_mkl(mklname, uhf)
 call read_mkl(mklname, uhf, print_mo)
 deallocate(shl2atm)
 if(ANY(nuc > 18)) then
  write(iout,'(/,A)') "Warning in subroutine mkl2gjf: element(s)>'Ar' detected."
  write(iout,'(A)') 'NOTE: the .mkl file does not contain ECP/PP information.&
                   & If you use ECP/PP'
  write(iout,'(A)') '(in ORCA .inp file), there would be no ECP in the genera&
                   &ted .gjf file. You'
  write(iout,'(A)') "should manually add ECP data into .gjf, and change 'gen'&
                   & into 'genecp'. If"
  write(iout,'(A)') 'you use all-electron basis set, there is no problem.'
 end if
 deallocate(nuc)

 write(fid,'(A)',advance='no') '#p'
 if(uhf) then
  write(fid,'(A)',advance='no') ' UHF/'
 else
  if(mult /= 1) then
   write(fid,'(A)',advance='no') ' ROHF/'
  else
   write(fid,'(A)',advance='no') ' RHF/'
  end if
 end if
 write(fid,'(A)',advance='no') 'gen int=nobasistransform'
 ! we do not know using gen or genecp, since ECP is not contained in .mkl

 if(print_mo) then
  write(fid,'(A)') ' nosymm guess=Cards'
 else
  write(fid,'(A)') ' nosymm'
 end if
 write(fid,'(/,A,/)') 'generated by utility mkl2gjf in MOKIT'
 write(fid,'(I0,1X,I0)') charge, mult

 ! print elements and Cartesian coordinates
 do i = 1, natom, 1
  write(fid,'(A2,3(1X,F18.8))') elem(i), coor(1:3,i)
 end do ! for i
 deallocate(elem, coor)
 write(fid,'(/)',advance='no')

 ! print basis set
 do i = 1, natom, 1
  write(fid,'(I0,A2)') i, ' 0'
  nc = all_pg(i)%nc

  do j = 1, nc, 1
   nline = all_pg(i)%prim_gau(j)%nline
   ncol = all_pg(i)%prim_gau(j)%ncol
   write(fid,'(A,2X,I0,A)') all_pg(i)%prim_gau(j)%stype, nline, '  1.00'

   do k = 1, nline, 1
    select case(ncol)
    case(2)
     write(fid,'(2ES20.10)') all_pg(i)%prim_gau(j)%coeff(k,1:2)
    case(3)
     write(fid,'(3ES20.10)') all_pg(i)%prim_gau(j)%coeff(k,1:3)
    case default
     write(iout,'(A)') 'ERROR in subroutine mkl2gjf: ncol out of range.'
     write(iout,'(A,I0)') 'ncol=', ncol
     stop
    end select
   end do ! for k
  end do ! for j

  write(fid,'(A)') '****'
 end do ! for i
 deallocate(all_pg)
 ! print basis set done

 if(.not. print_mo) then ! if no MOs required, return
  write(fid,'(/)')
  close(fid)
  deallocate(shell_type)
  return
 end if

 ! find F+3, G+3 and H+3 functions, multiply them by -1
 nf3mark = 0; ng3mark = 0; nh3mark = 0
 allocate(f3_mark(nbf), source=0)
 allocate(g3_mark(nbf), source=0)
 allocate(h3_mark(nbf), source=0)
 k = 0
 do i = 1, ncontr, 1
  select case(shell_type(i))
  case(0) ! S
   k = k + 1
  case(1) ! P
   k = k + 3
  case(-1) ! L
   k = k + 4
  case(-2) ! D
   k = k + 5
  case(-3) ! F
   k = k + 7
   nf3mark = nf3mark + 1
   f3_mark(nf3mark) = k - 1
  case(-4) ! G
   k = k + 9
   ng3mark = ng3mark + 1
   g3_mark(ng3mark) = k - 3
  case(-5) ! H
   k = k + 11
   nh3mark = nh3mark + 1
   h3_mark(nh3mark) = k - 5
  end select
 end do ! for i
 deallocate(shell_type)

 if(k /= nbf) then
  write(iout,'(A)') 'ERROR in subroutine mkl2gjf: k /= nbf!'
  write(iout,'(2(A,I0))') 'k=', k, ', nbf=', nbf
  stop
 end if

 do i = 1, nf3mark, 1
  alpha_coeff(f3_mark(i),:) = -alpha_coeff(f3_mark(i),:)
  alpha_coeff(f3_mark(i)+1,:) = -alpha_coeff(f3_mark(i)+1,:)
 end do ! for i
 do i = 1, ng3mark, 1
  alpha_coeff(g3_mark(i):g3_mark(i)+3,:) = -alpha_coeff(g3_mark(i):g3_mark(i)+3,:)
 end do ! for i
 do i = 1, nh3mark, 1
  alpha_coeff(h3_mark(i):h3_mark(i)+3,:) = -alpha_coeff(h3_mark(i):h3_mark(i)+3,:)
 end do ! for i

 if(uhf) then
  do i = 1, nf3mark, 1
   beta_coeff(f3_mark(i),:) = -beta_coeff(f3_mark(i),:)
   beta_coeff(f3_mark(i)+1,:) = -beta_coeff(f3_mark(i)+1,:)
  end do ! for i
  do i = 1, ng3mark, 1
   beta_coeff(g3_mark(i):g3_mark(i)+3,:) = -beta_coeff(g3_mark(i):g3_mark(i)+3,:)
  end do ! for i
  do i = 1, nh3mark, 1
   beta_coeff(h3_mark(i):h3_mark(i)+3,:) = -beta_coeff(h3_mark(i):h3_mark(i)+3,:)
  end do ! for i
 end if
 deallocate(f3_mark, g3_mark, h3_mark)

 write(fid,'(/,A)') '(5E18.10)'
 do i = 1, nif, 1
  write(fid,'(I5,A,E15.8)') i, ' Alpha MO OE=', ev_a(i)
  write(fid,'((5E18.10))') (alpha_coeff(j,i),j=1,nbf)
 end do ! for i
 deallocate(alpha_coeff, ev_a)

 if(uhf) then
  write(fid,'(/)',advance='no')
  do i = 1, nif, 1
   write(fid,'(I5,A,E15.8)') i, ' Beta MO OE=', ev_b(i)
   write(fid,'((5E18.10))') (beta_coeff(j,i),j=1,nbf)
  end do ! for i
  deallocate(beta_coeff, ev_b)
 end if

 write(fid,'(/)')
 close(fid)
 return
end subroutine mkl2gjf
