#!python
#cython: boundscheck=False
#cython: wraparound=False
#cython: initializedcheck=False
#cython: cdivision=True

cimport ParallelMPI
cimport Grid
cimport ReferenceState
cimport PrognosticVariables
cimport DiagnosticVariables

cimport PressureFFTSerial
cimport PressureFFTParallel

import numpy as np
cimport numpy as np


import cython

cdef class PressureSolver:
    def __init__(self):
        pass

    cpdef initialize(self,namelist, Grid.Grid Gr,ReferenceState.ReferenceState RS ,DiagnosticVariables.DiagnosticVariables DV, ParallelMPI.ParallelMPI PM):

        DV.add_variables('dynamic_pressure', 'Pa', r'p', 'dynamic pressure', 'sym', PM)
        DV.add_variables('press2', 'Pa', r'p', 'dynamic pressure', 'sym', PM)
        DV.add_variables('divergence', '1/s', r'd', '3d divergence', 'sym',PM)
        DV.add_variables('div1', '1/s', r'd', '3d divergence', 'sym',PM)
        DV.add_variables('div2', '1/s', r'd', '3d divergence', 'sym',PM)

        DV.add_variables('wBudget_PressureGradient', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_PressureGradient_RK0', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_PressureGradient_RK1', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_PressureGradient_RK2', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_PressureGradient_RK3', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_PressureGradient_RK4', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve_RK0', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve_RK1', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve_RK2', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve_RK3', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wBudget_removeHorAve_RK4', 'Pa m^2/kg', r'pgrad', 'pressure gradient', 'sym', PM)

        DV.add_variables('wtmp_beforeP', 'm/s', r'pgrad', 'pressure gradient', 'sym', PM)
        DV.add_variables('wtmp_afterP', 'm/s', r'pgrad', 'pressure gradient', 'sym', PM)

        self.divergence = np.zeros(Gr.dims.npl,dtype=np.double, order='c')
        #self.poisson_solver = PressureFFTSerial.PressureFFTSerial()
        self.poisson_solver = PressureFFTParallel.PressureFFTParallel()
        self.poisson_solver.initialize(Gr,RS,PM)

        return

    cpdef update(self,Grid.Grid Gr, ReferenceState.ReferenceState RS,
                  DiagnosticVariables.DiagnosticVariables DV, PrognosticVariables.PrognosticVariables PV, ParallelMPI.ParallelMPI PM):

        cdef:
            Py_ssize_t i
            Py_ssize_t d
            Py_ssize_t vel_shift
            Py_ssize_t u_shift = PV.get_varshift(Gr,'u')
            Py_ssize_t v_shift = PV.get_varshift(Gr,'v')
            Py_ssize_t w_shift = PV.get_varshift(Gr,'w')
            Py_ssize_t pres_shift = DV.get_varshift(Gr,'dynamic_pressure')
            Py_ssize_t div_shift = DV.get_varshift(Gr,'divergence')
            Py_ssize_t div1_shift = DV.get_varshift(Gr,'div1')
            Py_ssize_t div2_shift = DV.get_varshift(Gr,'div2')

            Py_ssize_t dpdz_shift = DV.get_varshift(Gr,'wBudget_PressureGradient')
            Py_ssize_t whor_shift = DV.get_varshift(Gr,'wBudget_removeHorAve')

            Py_ssize_t wbp_shift = DV.get_varshift(Gr,'wtmp_beforeP')
            Py_ssize_t wap_shift = DV.get_varshift(Gr,'wtmp_afterP')

        #Now compute the momentum divergence before removing w_mean
        with nogil:
            for i in xrange(Gr.dims.npg):
                DV.values[div1_shift + i] = 0.0
        for d in xrange(Gr.dims.dims):
            vel_shift = PV.velocity_directions[d]*Gr.dims.npg
            second_order_divergence(&Gr.dims, &RS.alpha0[0], &RS.alpha0_half[0],&PV.values[vel_shift],
                 &DV.values[div1_shift] ,d)

        #Remove mean u3
        cdef double [:] u3_mean = PM.HorizontalMean(Gr,&PV.values[w_shift])
        remove_mean_u3(&Gr.dims,&u3_mean[0],&PV.values[w_shift],&DV.values[whor_shift])

        #Now compute the momentum divergence after removing w_mean
        with nogil:
            for i in xrange(Gr.dims.npg):
                DV.values[div2_shift + i] = 0.0
        for d in xrange(Gr.dims.dims):
            vel_shift = PV.velocity_directions[d]*Gr.dims.npg
            second_order_divergence(&Gr.dims, &RS.alpha0[0], &RS.alpha0_half[0],&PV.values[vel_shift],
                 &DV.values[div2_shift] ,d)

        #Zero the divergence array [Perhaps we can replace this with a C-Call to Memset]
        with nogil:
            for i in xrange(Gr.dims.npg):
                DV.values[div_shift + i] = 0.0

        #Now compute the momentum divergence
        for d in xrange(Gr.dims.dims):
            vel_shift = PV.velocity_directions[d]*Gr.dims.npg
            second_order_divergence(&Gr.dims, &RS.alpha0[0], &RS.alpha0_half[0],&PV.values[vel_shift],
                 &DV.values[div_shift] ,d)

        #Now call the pressure solver
        self.poisson_solver.solve(Gr, RS, DV, PM)

        #Update pressure boundary condition
        p_nv = DV.name_index['dynamic_pressure']
        DV.communicate_variable(Gr,PM,p_nv)

        #Apply pressure correction
        for i in xrange(Gr.dims.npg):
            DV.values[wbp_shift+i] = PV.values[w_shift+i]

        second_order_pressure_correction(&Gr.dims,&DV.values[pres_shift],
                                         &PV.values[u_shift],&PV.values[v_shift],&PV.values[w_shift],
                                         &DV.values[dpdz_shift])

        for i in xrange(Gr.dims.npg):
            DV.values[wap_shift+i] = PV.values[w_shift+i]


        #Zero the divergence array [Perhaps we can replace this with a C-Call to Memset]
        with nogil:
            for i in xrange(Gr.dims.npg):
                DV.values[div_shift + i] = 0.0

        #Now compute the momentum divergence
        for d in xrange(Gr.dims.dims):
            vel_shift = PV.velocity_directions[d]*Gr.dims.npg
            second_order_divergence(&Gr.dims, &RS.alpha0[0], &RS.alpha0_half[0],&PV.values[vel_shift],
                 &DV.values[div_shift] ,d)

        #Switch this call at for a single variable boundary condition update
        PV.update_all_bcs(Gr,PM)

        return

cdef void second_order_pressure_correction(Grid.DimStruct *dims, double *p, double *u, double *v, double *w, double *press_grad ):

    cdef:
        Py_ssize_t imin = 0
        Py_ssize_t jmin = 0
        Py_ssize_t kmin = 0
        Py_ssize_t imax = dims.nlg[0] - 1
        Py_ssize_t jmax = dims.nlg[1] - 1
        Py_ssize_t kmax = dims.nlg[2] - 1
        Py_ssize_t istride = dims.nlg[1] * dims.nlg[2]
        Py_ssize_t jstride = dims.nlg[2]
        Py_ssize_t ishift, jshift
        Py_ssize_t i,j,k, ijk
        Py_ssize_t ip1 = istride
        Py_ssize_t jp1 = jstride
        Py_ssize_t kp1 = 1

        # Py_ssize_t dpdz_shift = DV.get_varshift(Gr,'wBudget_PressureGradient')

    for i in xrange(imin,imax):
        ishift = istride * i
        for j in xrange(jmin,jmax):
            jshift = jstride * j
            for k in xrange(kmin,kmax):
                ijk = ishift + jshift + k
                u[ijk] -=  (p[ijk + ip1] - p[ijk])*dims.dxi[0]
                v[ijk] -=  (p[ijk + jp1] - p[ijk])*dims.dxi[1]
                w[ijk] -=  (p[ijk + kp1] - p[ijk])*dims.dxi[2] * dims.imetl[k] #(p[ijk + kp1] - p[ijk])*dims.dxi[2]
                press_grad[ijk] = -(p[ijk + kp1] - p[ijk])*dims.dxi[2] * dims.imetl[k]


    return


cdef void remove_mean_u3(Grid.DimStruct *dims, double *u3_mean, double *velocity, double *whor):

    cdef:
        Py_ssize_t imin = 0
        Py_ssize_t jmin = 0
        Py_ssize_t kmin = 0
        Py_ssize_t imax = dims.nlg[0]
        Py_ssize_t jmax = dims.nlg[1]
        Py_ssize_t kmax = dims.nlg[2]
        Py_ssize_t istride = dims.nlg[1] * dims.nlg[2]
        Py_ssize_t jstride = dims.nlg[2]
        Py_ssize_t ishift, jshift
        Py_ssize_t ijk, i, j, k

    with nogil:
        for i in xrange(imin,imax):
            ishift = i*istride
            for j in xrange(jmin,jmax):
                jshift = j * jstride
                for k in xrange(kmin,kmax):
                     ijk = ishift + jshift + k
                     velocity[ijk] = velocity[ijk] - u3_mean[k]
                     whor[ijk] = -u3_mean[k]

    return

cdef void second_order_divergence(Grid.DimStruct *dims, double *alpha0, double *alpha0_half, double *velocity,
                                  double *divergence, Py_ssize_t d):

    cdef:
        Py_ssize_t imin = dims.gw
        Py_ssize_t jmin = dims.gw
        Py_ssize_t kmin = dims.gw
        Py_ssize_t imax = dims.nlg[0] - dims.gw
        Py_ssize_t jmax = dims.nlg[1] - dims.gw
        Py_ssize_t kmax = dims.nlg[2] - dims.gw
        Py_ssize_t istride = dims.nlg[1] * dims.nlg[2]
        Py_ssize_t jstride = dims.nlg[2]
        Py_ssize_t ishift, jshift
        Py_ssize_t i,j,k,ijk

        #Compute the s+trides given the dimensionality
        Py_ssize_t [3] p1 = [istride, jstride, 1]
        Py_ssize_t sm1 =  -p1[d]
        double dxi = 1.0/dims.dx[d]

    if d != 2:
        for i in xrange(imin,imax):
            ishift = i*istride
            for j in xrange(jmin,jmax):
                jshift = j * jstride
                for k in xrange(kmin,kmax):
                     ijk = ishift + jshift + k
                     divergence[ijk] += (velocity[ijk]/alpha0_half[k]  - velocity[ijk+sm1]/alpha0_half[k])*dxi
    else:
        for i in xrange(imin,imax):
            ishift = i*istride
            for j in xrange(jmin,jmax):
                jshift = j * jstride
                for k in xrange(kmin,kmax):
                     ijk = ishift + jshift + k
                     divergence[ijk] += ((velocity[ijk]) /alpha0[k] - (velocity[ijk+sm1])/alpha0[k-1])*dxi*dims.imetl_half[k]

    return
