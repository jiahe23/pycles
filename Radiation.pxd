cimport Grid
cimport ReferenceState
cimport PrognosticVariables
cimport DiagnosticVariables
from NetCDFIO cimport NetCDFIO_Stats
cimport ParallelMPI
from TimeStepping cimport TimeStepping
cimport Surface
from Forcing cimport ForcingReferenceBase

cdef class RadiationBase:
    cdef:
        double [:] heating_rate
        double [:] lw_heating_rate
        double [:] sw_heating_rate
        double [:] dTdt_rad
        double [:] uflux_lw
        double [:] dflux_lw
        double [:] uflux_sw
        double [:] dflux_sw
        double [:] heating_rate_clear
        double [:] lw_heating_rate_clear
        double [:] sw_heating_rate_clear
        double [:] uflux_lw_clear
        double [:] dflux_lw_clear
        double [:] uflux_sw_clear
        double [:] dflux_sw_clear
        double [:] temperature_localsum
        double [:] h2ovmr_localsum
        double [:] rl_localsum
        double [:] cliqwp_localsum
        double [:] cicewp_localsum
        double [:] cldfr_localsum
        double [:] h2ovmr_fix_wv
        ParallelMPI.Pencil z_pencil
        double srf_lw_down
        double srf_lw_up
        double srf_sw_down
        double srf_sw_up
        double toa_lw_down
        double toa_lw_up
        double toa_sw_down
        double toa_sw_up

        double srf_lw_down_clear
        double srf_lw_up_clear
        double srf_sw_down_clear
        double srf_sw_up_clear
        double toa_lw_down_clear
        double toa_lw_up_clear
        double toa_sw_down_clear
        double toa_sw_up_clear
        double swcre_srf

    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)
    cpdef init_from_restart(self, Restart)
    cpdef restart(self, Restart)
    cpdef initialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                              DiagnosticVariables.DiagnosticVariables DV,
                              Surface.SurfaceBase Sur, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa,
                              ForcingReferenceBase FoRef)
    cpdef update(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV, Surface.SurfaceBase Sur,
                 TimeStepping TS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef stats_io(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                   NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)

cdef class RadiationNone(RadiationBase):
    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)
    cpdef initialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                              Surface.SurfaceBase Sur, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef update(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV,
                 Surface.SurfaceBase Sur, TimeStepping TS,ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef stats_io(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                   NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)

cdef class RadiationDyCOMS_RF01(RadiationBase):
    cdef:
        double alpha_z
        double kap
        double f0
        double f1
        double divergence

    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)
    cpdef initialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                              Surface.SurfaceBase Sur,NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef update(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV,
                 Surface.SurfaceBase Sur,TimeStepping TS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef stats_io(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                   NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)

cdef class RadiationSmoke(RadiationBase):
    cdef:
        double f0
        double kap


    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)
    cpdef initialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                              Surface.SurfaceBase Sur, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef update(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV, Surface.SurfaceBase Sur,
                 TimeStepping TS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef stats_io(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                   NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)


cdef class RadiationRRTM(RadiationBase):
    cdef:
        str profile_name
        bint use_reference_class
        str reference_type
        bint fix_wv
        str fix_wv_statsfile
        double Tg_adiabat
        double Pg_adiabat
        double RH_adiabat
        Py_ssize_t n_buffer
        Py_ssize_t n_ext
        double stretch_factor
        double patch_pressure
        double [:] p_ext
        double [:] t_ext
        double [:] rv_ext
        double [:] p_full
        double [:] pi_full


        double co2_factor
        double h2o_factor
        double SST_1xCO2
        int dyofyr
        double dyofyr_real
        bint daily_mean_sw
        double hourz_init
        double hourz
        double latitude
        double longitude
        double scon
        double adjes
        double solar_constant
        double coszen
        double adif
        double adir
        bint constant_adir
        double radiation_frequency
        double next_radiation_calculate

        double [:] o3vmr
        double [:] co2vmr
        double [:] ch4vmr
        double [:] n2ovmr
        double [:] o2vmr
        double [:] cfc11vmr
        double [:] cfc12vmr
        double [:] cfc22vmr
        double [:] ccl4vmr
        bint uniform_reliq


    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)
    cpdef initialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                              DiagnosticVariables.DiagnosticVariables DV, Surface.SurfaceBase Sur,
                              NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa, ForcingReferenceBase FoRef)
    cpdef reinitialize_profiles(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                                DiagnosticVariables.DiagnosticVariables DV,
                              Surface.SurfaceBase Sur, ParallelMPI.ParallelMPI Pa,
                                ForcingReferenceBase FoRef,TimeStepping TS)
    cpdef update(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV,
                 Surface.SurfaceBase Sur, TimeStepping TS, ParallelMPI.ParallelMPI Pa,
                 ForcingReferenceBase FoRef)
    cdef update_RRTM(self, Grid.Grid Gr, ReferenceState.ReferenceState Ref,
                 PrognosticVariables.PrognosticVariables PV, DiagnosticVariables.DiagnosticVariables DV,
                     Surface.SurfaceBase Sur,ParallelMPI.ParallelMPI Pa)
    cpdef stats_io(self, Grid.Grid Gr,  ReferenceState.ReferenceState Ref, DiagnosticVariables.DiagnosticVariables DV,
                   NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa)

