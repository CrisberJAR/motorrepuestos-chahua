-- Paso 3 · generar_planilla solo actualiza filas cuyos valores cambiaron
-- (evita eventos de tiempo real innecesarios en la web y la app).
create or replace function public.generar_planilla(p_periodo text)
returns setof public.pagos
language plpgsql security definer
set search_path = public
as $$
declare
  v_desde date;
  v_hasta date;
  r       record;
begin
  if not public.puede_administrar() then
    raise exception 'Solo el administrador puede generar la planilla';
  end if;
  if p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Periodo inválido: usa el formato AAAA-MM, por ejemplo 2026-11';
  end if;

  v_desde := to_date(p_periodo || '-01', 'YYYY-MM-DD');
  v_hasta := least((v_desde + interval '1 month' - interval '1 day')::date, public.hoy_lima());

  for r in
    select p.id,
           p.pago_por_dia,
           count(*) filter (where d.estado in ('asistio','tardanza'))           as asistidos,
           count(*) filter (where d.estado = 'permiso')                         as permisos,
           count(*) filter (where d.estado = 'permiso' and d.permiso_con_goce)  as permisos_pagados,
           count(*) filter (where d.estado = 'falta')                           as faltas,
           count(*) filter (where d.estado = 'tardanza')                        as tardanzas
      from public.personal p
      join public.detalle_asistencia(v_desde, v_hasta, null) d on d.personal_id = p.id
     where p.estado = 'activo'
     group by p.id, p.pago_por_dia
  loop
    insert into public.pagos as pg (
      personal_id, periodo_mes, dias_asistidos, dias_permiso, dias_permiso_pagado,
      dias_falta, tardanzas_acumuladas, pago_por_dia, monto_base
    )
    values (
      r.id, p_periodo, r.asistidos, r.permisos, r.permisos_pagados,
      r.faltas, r.tardanzas, r.pago_por_dia,
      (r.asistidos + r.permisos_pagados) * r.pago_por_dia
    )
    on conflict (personal_id, periodo_mes) do update
       set dias_asistidos       = excluded.dias_asistidos,
           dias_permiso         = excluded.dias_permiso,
           dias_permiso_pagado  = excluded.dias_permiso_pagado,
           dias_falta           = excluded.dias_falta,
           tardanzas_acumuladas = excluded.tardanzas_acumuladas,
           pago_por_dia         = excluded.pago_por_dia,
           monto_base           = excluded.monto_base
     where pg.estado_pago = 'pendiente'
       and (pg.dias_asistidos, pg.dias_permiso, pg.dias_permiso_pagado, pg.dias_falta,
            pg.tardanzas_acumuladas, pg.pago_por_dia, pg.monto_base)
           is distinct from
           (excluded.dias_asistidos, excluded.dias_permiso, excluded.dias_permiso_pagado, excluded.dias_falta,
            excluded.tardanzas_acumuladas, excluded.pago_por_dia, excluded.monto_base);
  end loop;

  return query
    select pg.* from public.pagos pg where pg.periodo_mes = p_periodo;
end;
$$;
