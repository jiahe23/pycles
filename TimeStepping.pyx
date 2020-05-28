#!python
#cython: boundscheck=False
#cython: wraparound=False
#cython: initializedcheck=False
#cython: cdivision=True

cimport ParallelMPI as ParallelMPI
cimport PrognosticVariables as PrognosticVariables
cimport DiagnosticVariables as DiagnosticVariables
cimport Grid as Grid
cimport Restart
cimport mpi4py.libmpi as mpi

import numpy as np
cimport numpy as np

from libc.math cimport fmin, fmax, fabs

cdef class TimeStepping:

    def __init__(self):

        return

    cpdef initialize(self,namelist,PrognosticVariables.PrognosticVariables PV, ParallelMPI.ParallelMPI Pa):

        #Get the time stepping potions from the name list
        try:
            self.ts_type = namelist['time_stepping']['ts_type']
        except:
            Pa.root_print('ts_type not given in namelist')
            Pa.root_print('Killing simulation now')
            Pa.kill()

        try:
            self.dt = namelist['time_stepping']['dt_initial']
        except:
            Pa.root_print('dt_initial (initial time step) not given in namelist so taking defualt value dt_initail = 1.0')
            self.dt = 1.0

        try:
            self.dt_max = namelist['time_stepping']['dt_max']
        except:
            Pa.root_print('dt_max (maximum permissible time step) not given in namelist so taking default value dt_max =10.0')
            self.dt_max = 10.0

        try:
            self.t = namelist['time_stepping']['t']
        except:
            Pa.root_print('t (initial time) not given in namelist so taking default value t = 0')
            self.t = 0.0

        try:
            self.cfl_limit = namelist['time_stepping']['cfl_limit']
        except:
            Pa.root_print('cfl_limit (maximum permissible cfl number) not given in namelist so taking default value cfl_max=0.7')
            self.cfl_limit = 0.7

        try:
            self.t_max = namelist['time_stepping']['t_max']
        except:
            Pa.root_print('t_max (time at end of simulation) not given in name list! Killing Simulation Now')
            Pa.kill()

        #Now initialize the correct time stepping routine
        if self.ts_type == 2:
            self.initialize_second(PV)
        elif self.ts_type == 3:
            self.initialize_third(PV)
        elif self.ts_type == 4:
            self.initialize_fourth(PV)
        else:
            Pa.root_print('Invalid ts_type: ' + str(self.ts_type))
            Pa.root_print('Killing simulation now')
            Pa.kill()

        return


    cpdef update(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV, ParallelMPI.ParallelMPI Pa):

        if self.ts_type == 2:
            self.update_second(Gr,PV,DV)
        elif self.ts_type == 3:
            self.update_third(Gr,PV,DV)
        elif self.ts_type == 4:
            self.update_fourth(Gr,PV)
        else:
            Pa.root_print('Time stepping option not found ts_type = ' + str(self.ts_type))
            Pa.root_print('Killing Simulation Now!')
            Pa.kill()
        return

    cpdef update_pressure(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV, ParallelMPI.ParallelMPI Pa):

        if self.ts_type == 2:
            self.update_pressure_second(Gr,PV,DV)
        elif self.ts_type == 3:
            self.update_pressure_third(Gr,PV,DV)
        elif self.ts_type == 4:
            self.update_pressure_fourth(Gr,PV,DV)
        else:
            Pa.root_print('Time stepping option not found ts_type = ' + str(self.ts_type))
            Pa.root_print('Killing Simulation Now!')
            Pa.kill()
        return


    cpdef adjust_timestep(self,Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV, ParallelMPI.ParallelMPI Pa):
        #Compute the CFL number and diffusive stability criterion
        if self.rk_step == self.n_rk_steps - 1:
            self.compute_cfl_max(Gr, PV,DV, Pa)
            self.dt = self.cfl_time_step()

            #Diffusive limiting not yet implemented
            if self.t + self.dt > self.t_max:
                self.dt = self.t_max - self.t

            if self.dt < 0.0:
                Pa.root_print('dt = '+ str(self.dt)+ " killing simulation!")
                Pa.kill()

        return


    cpdef update_second(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV):

        cdef:
            Py_ssize_t i
            Py_ssize_t w_shift = PV.get_varshift(Gr, 'w')

            Py_ssize_t wadv_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection')
            Py_ssize_t wadv_rk0_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection_RK0')
            Py_ssize_t wadv_rk1_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection_RK1')

            Py_ssize_t wdiff_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion')
            Py_ssize_t wdiff_rk0_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion_RK0')
            Py_ssize_t wdiff_rk1_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion_RK1')

            Py_ssize_t wbuoy_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy')
            Py_ssize_t wbuoy_rk0_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy_RK0')
            Py_ssize_t wbuoy_rk1_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy_RK1')

            Py_ssize_t wtdc_shift = DV.get_varshift(Gr, 'wBudget_TDC')
            Py_ssize_t wtdc_rk0_shift = DV.get_varshift(Gr, 'wBudget_TDC_RK0')
            Py_ssize_t wtdc_rk1_shift = DV.get_varshift(Gr, 'wBudget_TDC_RK1')

            Py_ssize_t wrk0_in_shift = DV.get_varshift(Gr, 'wBudget_TSin')

        with nogil:
            if self.rk_step == 0:

                if self.t % self.dt_max == 0.0:
                    for i in xrange(Gr.dims.npg):
                        DV.values[wrk0_in_shift+i] = PV.values[w_shift+i]
                        DV.values[wadv_rk0_shift+i] = 0.0
                        DV.values[wdiff_rk0_shift+i] = 0.0
                        DV.values[wbuoy_rk0_shift+i] = 0.0
                        DV.values[wtdc_rk0_shift+i] = 0.0
                        DV.values[wadv_rk1_shift+i] = 0.0
                        DV.values[wdiff_rk1_shift+i] = 0.0
                        DV.values[wbuoy_rk1_shift+i] = 0.0
                        DV.values[wtdc_rk1_shift+i] = 0.0

                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_rk0_shift+i] += DV.values[wadv_shift+i]*self.dt
                    DV.values[wdiff_rk0_shift+i] += DV.values[wdiff_shift+i]*self.dt
                    DV.values[wbuoy_rk0_shift+i] += DV.values[wbuoy_shift+i]*self.dt
                    DV.values[wtdc_rk0_shift+i] += PV.tendencies[w_shift+i]*self.dt

                for i in xrange(Gr.dims.npg*PV.nv):
                    self.value_copies[0,i] = PV.values[i]
                    PV.values[i] += PV.tendencies[i]*self.dt
                    PV.tendencies[i] = 0.0


            else:
                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_rk1_shift+i] += DV.values[wadv_shift+i]*self.dt
                    DV.values[wdiff_rk1_shift+i] += DV.values[wdiff_shift+i]*self.dt
                    DV.values[wbuoy_rk1_shift+i] += DV.values[wbuoy_shift+i]*self.dt
                    DV.values[wtdc_rk1_shift+i] += PV.tendencies[w_shift+i]*self.dt

                for i in xrange(Gr.dims.npg*PV.nv):
                    PV.values[i] = 0.5 * (self.value_copies[0,i] + PV.values[i] + PV.tendencies[i] * self.dt)
                    PV.tendencies[i] = 0.0

                self.t += self.dt

            if self.rk_step == 1:
                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_shift+i] = (DV.values[wadv_rk1_shift+i]+DV.values[wadv_rk0_shift+i])*0.5
                    DV.values[wdiff_shift+i] = (DV.values[wdiff_rk1_shift+i]+DV.values[wdiff_rk0_shift+i])*0.5
                    DV.values[wbuoy_shift+i] = (DV.values[wbuoy_rk1_shift+i]+DV.values[wbuoy_rk0_shift+i])*0.5
                    DV.values[wtdc_shift+i] = (DV.values[wtdc_rk1_shift+i]+DV.values[wtdc_rk0_shift+i])*0.5

        return

    cpdef update_pressure_second(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV):
        cdef:
            Py_ssize_t i
            Py_ssize_t press_shift = DV.get_varshift(Gr, 'dynamic_pressure')

            Py_ssize_t whor_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve')
            Py_ssize_t whor_rk0_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK0')
            Py_ssize_t whor_rk1_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK1')

            Py_ssize_t wpress_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient')
            Py_ssize_t wpress_rk0_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK0')
            Py_ssize_t wpress_rk1_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK1')


        with nogil:
            if self.rk_step == 0:
                if self.t % self.dt_max == 0.0:
                    for i in xrange(Gr.dims.npg):
                        DV.values[whor_rk0_shift+i] = 0.0
                        DV.values[wpress_rk0_shift+i] = 0.0
                        DV.values[whor_rk1_shift+i] = 0.0
                        DV.values[wpress_rk1_shift+i] = 0.0

                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk0_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk0_shift+i] += DV.values[wpress_shift+i]
            else:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk1_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk1_shift+i] += DV.values[wpress_shift+i]

                    DV.values[press_shift+i] = DV.values[press_shift+i]/self.dt

                    DV.values[whor_shift+i] = DV.values[whor_rk1_shift+i] + DV.values[whor_rk0_shift+i]*0.5
                    DV.values[wpress_shift+i] = DV.values[wpress_rk1_shift+i] + DV.values[wpress_rk0_shift+i]*0.5

        return


    cpdef update_third(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV):
        cdef:
            Py_ssize_t i
            Py_ssize_t w_shift = PV.get_varshift(Gr, 'w')

            Py_ssize_t wadv_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection')
            Py_ssize_t wadv_rk0_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection_RK0')
            Py_ssize_t wadv_rk1_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection_RK1')
            Py_ssize_t wadv_rk2_shift = DV.get_varshift(Gr, 'wBudget_MomentumAdvection_RK2')

            Py_ssize_t wdiff_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion')
            Py_ssize_t wdiff_rk0_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion_RK0')
            Py_ssize_t wdiff_rk1_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion_RK1')
            Py_ssize_t wdiff_rk2_shift = DV.get_varshift(Gr, 'wBudget_MomentumDiffusion_RK2')

            Py_ssize_t wbuoy_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy')
            Py_ssize_t wbuoy_rk0_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy_RK0')
            Py_ssize_t wbuoy_rk1_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy_RK1')
            Py_ssize_t wbuoy_rk2_shift = DV.get_varshift(Gr, 'wBudget_Buoyancy_RK2')

            Py_ssize_t wtdc_shift = DV.get_varshift(Gr, 'wBudget_TDC')
            Py_ssize_t wtdc_rk0_shift = DV.get_varshift(Gr, 'wBudget_TDC_RK0')
            Py_ssize_t wtdc_rk1_shift = DV.get_varshift(Gr, 'wBudget_TDC_RK1')
            Py_ssize_t wtdc_rk2_shift = DV.get_varshift(Gr, 'wBudget_TDC_RK2')

            Py_ssize_t wrk0_in_shift = DV.get_varshift(Gr, 'wBudget_TSin')

        with nogil:
            if self.rk_step == 0:

                if self.t % self.dt_max == 0.0:
                    for i in xrange(Gr.dims.npg):
                        DV.values[wrk0_in_shift+i] = PV.values[w_shift+i]
                        DV.values[wadv_rk0_shift+i] = 0.0
                        DV.values[wdiff_rk0_shift+i] = 0.0
                        DV.values[wbuoy_rk0_shift+i] = 0.0
                        DV.values[wtdc_rk0_shift+i] = 0.0
                        DV.values[wadv_rk1_shift+i] = 0.0
                        DV.values[wdiff_rk1_shift+i] = 0.0
                        DV.values[wbuoy_rk1_shift+i] = 0.0
                        DV.values[wtdc_rk1_shift+i] = 0.0
                        DV.values[wadv_rk2_shift+i] = 0.0
                        DV.values[wdiff_rk2_shift+i] = 0.0
                        DV.values[wbuoy_rk2_shift+i] = 0.0
                        DV.values[wtdc_rk2_shift+i] = 0.0

                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_rk0_shift+i] += DV.values[wadv_shift+i]*self.dt
                    DV.values[wdiff_rk0_shift+i] += DV.values[wdiff_shift+i]*self.dt
                    DV.values[wbuoy_rk0_shift+i] += DV.values[wbuoy_shift+i]*self.dt
                    DV.values[wtdc_rk0_shift+i] += PV.tendencies[w_shift+i]*self.dt

                for i in xrange(Gr.dims.npg*PV.nv):
                    self.value_copies[0,i] = PV.values[i]
                    PV.values[i] += PV.tendencies[i]*self.dt
                    PV.tendencies[i] = 0.0

            elif self.rk_step == 1:
                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_rk1_shift+i] += DV.values[wadv_shift+i]*self.dt
                    DV.values[wdiff_rk1_shift+i] += DV.values[wdiff_shift+i]*self.dt
                    DV.values[wbuoy_rk1_shift+i] += DV.values[wbuoy_shift+i]*self.dt
                    DV.values[wtdc_rk1_shift+i] += PV.tendencies[w_shift+i]*self.dt

                for i in xrange(Gr.dims.npg*PV.nv):
                    PV.values[i] = 0.75 * self.value_copies[0,i] +  0.25*(PV.values[i] + PV.tendencies[i]*self.dt)
                    PV.tendencies[i] = 0.0
            else:
                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_rk2_shift+i] += DV.values[wadv_shift+i]*self.dt
                    DV.values[wdiff_rk2_shift+i] += DV.values[wdiff_shift+i]*self.dt
                    DV.values[wbuoy_rk2_shift+i] += DV.values[wbuoy_shift+i]*self.dt
                    DV.values[wtdc_rk2_shift+i] += PV.tendencies[w_shift+i]*self.dt

                for i in xrange(Gr.dims.npg*PV.nv):
                    PV.values[i] = (1.0/3.0) * self.value_copies[0,i] + (2.0/3.0)*(PV.values[i] + PV.tendencies[i]*self.dt)
                    PV.tendencies[i] = 0.0
                self.t += self.dt

            if self.rk_step == 2:
                for i in xrange(Gr.dims.npg):
                    DV.values[wadv_shift+i] = (DV.values[wadv_rk2_shift+i]*2.0/3.0
                                                +DV.values[wadv_rk1_shift+i]/6.0+DV.values[wadv_rk0_shift+i]/6.0)
                    DV.values[wdiff_shift+i] = (DV.values[wdiff_rk2_shift+i]*2.0/3.0
                                                +DV.values[wdiff_rk1_shift+i]/6.0+DV.values[wdiff_rk0_shift+i]/6.0)
                    DV.values[wbuoy_shift+i] = (DV.values[wbuoy_rk2_shift+i]*2.0/3.0
                                                +DV.values[wbuoy_rk1_shift+i]/6.0+DV.values[wbuoy_rk0_shift+i]/6.0)
                    DV.values[wtdc_shift+i] = (DV.values[wtdc_rk2_shift+i]*2.0/3.0
                                                +DV.values[wtdc_rk1_shift+i]/6.0+DV.values[wtdc_rk0_shift+i]/6.0)


        return

    cpdef update_pressure_third(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV):
        cdef:
            Py_ssize_t i
            Py_ssize_t press_shift = DV.get_varshift(Gr, 'dynamic_pressure')

            Py_ssize_t whor_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve')
            Py_ssize_t whor_rk0_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK0')
            Py_ssize_t whor_rk1_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK1')
            Py_ssize_t whor_rk2_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK2')

            Py_ssize_t wpress_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient')
            Py_ssize_t wpress_rk0_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK0')
            Py_ssize_t wpress_rk1_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK1')
            Py_ssize_t wpress_rk2_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK2')

        with nogil:
            if self.rk_step == 0:
                if self.t % self.dt_max == 0.0:
                    for i in xrange(Gr.dims.npg):
                        DV.values[whor_rk0_shift+i] = 0.0
                        DV.values[wpress_rk0_shift+i] = 0.0
                        DV.values[whor_rk1_shift+i] = 0.0
                        DV.values[wpress_rk1_shift+i] = 0.0
                        DV.values[whor_rk2_shift+i] = 0.0
                        DV.values[wpress_rk2_shift+i] = 0.0

                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk0_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk0_shift+i] += DV.values[wpress_shift+i]

            elif self.rk_step == 1:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk1_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk1_shift+i] += DV.values[wpress_shift+i]

            else:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk2_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk2_shift+i] += DV.values[wpress_shift+i]

                    DV.values[press_shift+i] = DV.values[press_shift+i]/self.dt

                    DV.values[whor_shift+i] = (DV.values[whor_rk2_shift+i] + (2.0/3.0)*DV.values[whor_rk1_shift+i]
                                               + (1.0/6.0)*DV.values[whor_rk0_shift+i] )
                    DV.values[wpress_shift+i] = (DV.values[wpress_rk2_shift+i] + (2.0/3.0)*DV.values[wpress_rk1_shift+i]
                                               + (1.0/6.0)*DV.values[wpress_rk0_shift+i] )

        return


    cpdef update_fourth(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV):
        cdef:
            Py_ssize_t i

        with nogil:
            if self.rk_step == 0:
                for i in xrange(Gr.dims.npg*PV.nv):
                    self.value_copies[0,i] = PV.values[i]
                    PV.values[i] += 0.391752226571890 * PV.tendencies[i]*self.dt
                    PV.tendencies[i] = 0.0
            elif self.rk_step == 1:
                for i in xrange(Gr.dims.npg*PV.nv):
                    PV.values[i] = (0.444370493651235*self.value_copies[0,i] + 0.555629506348765*PV.values[i]
                                    + 0.368410593050371*PV.tendencies[i]*self.dt )
                    PV.tendencies[i] = 0.0
            elif self.rk_step == 2:
                for i in xrange(Gr.dims.npg*PV.nv):
                    self.value_copies[1,i] = PV.values[i]
                    PV.values[i] = (0.620101851488403*self.value_copies[0,i] + 0.379898148511597*PV.values[i]
                                    + 0.251891774271694*PV.tendencies[i]*self.dt)
                    PV.tendencies[i] = 0.0
            elif self.rk_step == 3:
                for i in xrange(Gr.dims.npg*PV.nv):
                    self.value_copies[2,i] = PV.values[i]
                    self.tendency_copies[0,i] = PV.tendencies[i]
                    PV.values[i] = (0.178079954393132*self.value_copies[0,i] + 0.821920045606868*PV.values[i]
                                    + 0.544974750228521*PV.tendencies[i]*self.dt)
                    PV.tendencies[i] = 0.0
            else:
                for i in xrange(Gr.dims.npg*PV.nv):
                    PV.values[i] = (0.517231671970585*self.value_copies[1,i]
                                    + 0.096059710526147*self.value_copies[2,i] +0.063692468666290*self.tendency_copies[0,i]*self.dt
                                    + 0.386708617503269*PV.values[i] + 0.226007483236906*PV.tendencies[i]*self.dt)
                    PV.tendencies[i] = 0.0
                self.t += self.dt
        return

    cpdef update_pressure_fourth(self, Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV):
        cdef:
            Py_ssize_t i
            Py_ssize_t press_shift = DV.get_varshift(Gr, 'dynamic_pressure')

            Py_ssize_t whor_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve')
            Py_ssize_t whor_rk0_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK0')
            Py_ssize_t whor_rk1_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK1')
            Py_ssize_t whor_rk2_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK2')
            Py_ssize_t whor_rk3_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK3')
            Py_ssize_t whor_rk4_shift = DV.get_varshift(Gr, 'wBudget_removeHorAve_RK4')

            Py_ssize_t wpress_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient')
            Py_ssize_t wpress_rk0_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK0')
            Py_ssize_t wpress_rk1_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK1')
            Py_ssize_t wpress_rk2_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK2')
            Py_ssize_t wpress_rk3_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK3')
            Py_ssize_t wpress_rk4_shift = DV.get_varshift(Gr, 'wBudget_PressureGradient_RK4')

            double a1, a2, a3

        a1 = 0.386708617503269
        a2 = 0.096059710526147+a1*0.821920045606868
        a3 = 0.517231671970585+a2*0.379898148511597
        a4 = 0.555629506348765*a3

        with nogil:
            if self.rk_step == 0:
                if self.t % self.dt_max == 0.0:
                    for i in xrange(Gr.dims.npg):
                        DV.values[whor_rk0_shift+i] = 0.0
                        DV.values[wpress_rk0_shift+i] = 0.0
                        DV.values[whor_rk1_shift+i] = 0.0
                        DV.values[wpress_rk1_shift+i] = 0.0
                        DV.values[whor_rk2_shift+i] = 0.0
                        DV.values[wpress_rk2_shift+i] = 0.0

                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk0_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk0_shift+i] += DV.values[wpress_shift+i]

            elif self.rk_step == 1:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk1_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk1_shift+i] += DV.values[wpress_shift+i]

            elif self.rk_step == 2:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk2_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk2_shift+i] += DV.values[wpress_shift+i]

            elif self.rk_step == 3:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk3_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk3_shift+i] += DV.values[wpress_shift+i]

            else:
                for i in xrange(Gr.dims.npg):
                    DV.values[whor_rk4_shift+i] += DV.values[whor_shift+i]
                    DV.values[wpress_rk4_shift+i] += DV.values[wpress_shift+i]

                    DV.values[press_shift+i] = DV.values[press_shift+i]/self.dt

                    DV.values[whor_shift+i] = (DV.values[whor_rk3_shift+i] + a1*DV.values[whor_rk2_shift+i]
                                               + a2*DV.values[whor_rk1_shift+i] + a3*DV.values[whor_rk0_shift+i] )

                    DV.values[wpress_shift+i] = (DV.values[wpress_rk4_shift+i] + a1*DV.values[wpress_rk3_shift+i]
                                               + a2*DV.values[wpress_rk2_shift+i] + a3*DV.values[wpress_rk1_shift+i]
                                               + a4*DV.values[wpress_rk0_shift+i] )

        return



    cdef void initialize_second(self,PrognosticVariables.PrognosticVariables PV):

        self.rk_step = 0
        self.n_rk_steps = 2

        #Initialize storage
        self.value_copies = np.zeros((1,PV.values.shape[0]),dtype=np.double,order='c')
        self.tendency_copies = None

        return

    cdef void initialize_third(self,PrognosticVariables.PrognosticVariables PV):

        self.rk_step = 0
        self.n_rk_steps = 3

        #Initialize storage
        self.value_copies = np.zeros((1,PV.values.shape[0]),dtype=np.double,order='c')
        self.tendency_copies = None

        return

    cdef void initialize_fourth(self,PrognosticVariables.PrognosticVariables PV):
        self.rk_step = 0
        self.n_rk_steps = 5

        #Initialize storage
        self.value_copies = np.zeros((3,PV.values.shape[0]),dtype=np.double,order='c')
        self.tendency_copies = np.zeros((1,PV.values.shape[0]),dtype=np.double,order='c')

        return

    cdef void compute_cfl_max(self,Grid.Grid Gr, PrognosticVariables.PrognosticVariables PV,DiagnosticVariables.DiagnosticVariables DV, ParallelMPI.ParallelMPI Pa):

        cdef:
            double cfl_max_local = -9999.0
            double [3] dxi = Gr.dims.dxi
            Py_ssize_t u_shift = PV.get_varshift(Gr,'u')
            Py_ssize_t v_shift = PV.get_varshift(Gr,'v')
            Py_ssize_t w_shift = PV.get_varshift(Gr,'w')
            Py_ssize_t imin = Gr.dims.gw
            Py_ssize_t jmin = Gr.dims.gw
            Py_ssize_t kmin = Gr.dims.gw
            Py_ssize_t imax = Gr.dims.nlg[0] - Gr.dims.gw
            Py_ssize_t jmax = Gr.dims.nlg[1] - Gr.dims.gw
            Py_ssize_t kmax = Gr.dims.nlg[2] - Gr.dims.gw
            Py_ssize_t istride = Gr.dims.nlg[1] * Gr.dims.nlg[2]
            Py_ssize_t jstride = Gr.dims.nlg[2]
            Py_ssize_t i,j,k, ijk, ishift, jshift
            double w
            Py_ssize_t isedv

        with nogil:
            for i in xrange(imin,imax):
                ishift = i * istride
                for j in xrange(jmin,jmax):
                    jshift = j * jstride
                    for k in xrange(kmin,kmax):
                        ijk = ishift + jshift + k
                        w = fabs(PV.values[w_shift+ijk])
                        for isedv in xrange(DV.nsedv):
                            w = fmax(fabs( DV.values[DV.sedv_index[isedv]*Gr.dims.npg + ijk ] + PV.values[w_shift+ijk]), w)

                        cfl_max_local = fmax(cfl_max_local, self.dt * (fabs(PV.values[u_shift + ijk])*dxi[0] + fabs(PV.values[v_shift+ijk])*dxi[1] + w*(1.0/Gr.dzpl[k])))

        mpi.MPI_Allreduce(&cfl_max_local,&self.cfl_max,1,
                          mpi.MPI_DOUBLE,mpi.MPI_MAX,Pa.comm_world)

        self.cfl_max += 1e-11

        if self.cfl_max < 0.0:
            Pa.root_print('CFL_MAX = '+ str(self.cfl_max)+ " killing simulation!!!")
            Pa.kill()
        return

    cdef inline double cfl_time_step(self):
        return fmin(self.dt_max,self.cfl_limit/(self.cfl_max/self.dt))

    cpdef restart(self, Restart.Restart Re):
        Re.restart_data['TS'] = {}
        Re.restart_data['TS']['t'] = self.t
        Re.restart_data['TS']['dt'] = self.dt

        return
