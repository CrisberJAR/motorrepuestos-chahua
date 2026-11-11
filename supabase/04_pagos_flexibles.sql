-- =====================================================================
-- 04 · Pagos flexibles, pago por rendimiento y perfil del usuario
--
--  · Un pago cubre cualquier rango de fechas (semana, quincena, mes o días
--    sueltos): el administrador paga cuando el trabajador lo solicita.
--  · Pago por día fijo o variable (rendimiento): cada día asistido puede
--    tener su propio monto (asistencias.monto_dia). Si no tiene monto, se usa
--    el pago por día de referencia del trabajador.
--  · Cada pago guarda el método (efectivo, Yape, Plin, transferencia, otro)
--    y el número de operación.
--  · Lo pendiente se calcula en vivo: desde el día siguiente al último pago
--    hasta hoy.
--  · Foto de perfil, teléfono y correo editables por cada usuario.
-- =====================================================================

create extension if not exists btree_gist with schema extensions;

-- ---------- personal ----------
alter table public.personal
  add column if not exists tipo_pago       text not null default 'fijo',
  add column if not exists foto_perfil_url text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personal_tipo_pago_valido') then
    alter table public.personal
      add constraint personal_tipo_pago_valido check (tipo_pago in ('fijo','variable'));
  end if;
end $$;

comment on column public.personal.tipo_pago is 'fijo = gana su pago por día; variable = el admin registra el monto de cada día según su rendimiento';
comment on column public.personal.foto_perfil_url is 'Ruta en el bucket privado fotos_perfil, p. ej. <personal_id>/perfil.jpg';

-- ---------- asistencias: monto ganado en el día ----------
alter table public.asistencias
  add column if not exists monto_dia numeric(10,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'asistencias_monto_dia_valido') then
    alter table public.asistencias
      add constraint asistencias_monto_dia_valido check (monto_dia is null or monto_dia >= 0);
  end if;
end $$;

comment on column public.asistencias.monto_dia is 'Monto ganado ese día (pago por rendimiento). Null = se usa personal.pago_por_dia';

-- ---------- pagos: rango libre, método y operación ----------
alter table public.pagos
  add column if not exists fecha_desde       date,
  add column if not exists fecha_hasta       date,
  add column if not exists metodo_pago       text,
  add column if not exists numero_operacion  text,
  add column if not exists registrado_por    uuid references public.personal(id) on delete set null;

-- Los pagos de antes eran por mes completo
update public.pagos
   set fecha_desde = to_date(periodo_mes || '-01', 'YYYY-MM-DD'),
       fecha_hasta = (to_date(periodo_mes || '-01', 'YYYY-MM-DD') + interval '1 month' - interval '1 day')::date
 where fecha_desde is null;

-- Las filas "pendiente" eran estimaciones de planilla; ahora lo pendiente se calcula en vivo.
delete from public.pagos where estado_pago = 'pendiente';
update public.pagos set metodo_pago = 'efectivo' where metodo_pago is null;

alter table public.pagos
  alter column fecha_desde set not null,
  alter column fecha_hasta set not null,
  alter column metodo_pago set not null,
  alter column metodo_pago set default 'efectivo',
  alter column periodo_mes drop not null,
  alter column estado_pago set default 'pagado';

alter table public.pagos drop constraint if exists pagos_unico_por_periodo;
alter table public.pagos drop constraint if exists pagos_periodo_mes_check;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pagos_rango_valido') then
    alter table public.pagos add constraint pagos_rango_valido check (fecha_hasta >= fecha_desde);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pagos_metodo_valido') then
    alter table public.pagos add constraint pagos_metodo_valido
      check (metodo_pago in ('efectivo','yape','plin','transferencia','otro'));
  end if;
  -- Un mismo día no se puede pagar dos veces al mismo trabajador
  if not exists (select 1 from pg_constraint where conname = 'pagos_sin_cruce') then
    alter table public.pagos add constraint pagos_sin_cruce
      exclude using gist (personal_id with =, daterange(fecha_desde, fecha_hasta, '[]') with &&);
  end if;
end $$;

create index if not exists pagos_personal_rango_idx on public.pagos (personal_id, fecha_hasta desc);
create index if not exists pagos_fecha_pago_idx on public.pagos (fecha_pago);

-- Un día ya pagado no puede cambiar de monto
create or replace function public.asistencias_proteger_pagado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.monto_dia is distinct from old.monto_dia and exists (
    select 1 from public.pagos
     where personal_id = new.personal_id and new.fecha between fecha_desde and fecha_hasta
  ) then
    raise exception 'El día % ya fue pagado: anula ese pago antes de cambiar el monto.', to_char(new.fecha, 'DD/MM/YYYY');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_asistencias_proteger_pagado on public.asistencias;
create trigger trg_asistencias_proteger_pagado
  before update of monto_dia on public.asistencias
  for each row execute function public.asistencias_proteger_pagado();

-- La planilla mensual se reemplaza por pagos con rango libre
drop function if exists public.generar_planilla(text);

-- =====================================================================
-- Funciones
-- =====================================================================

-- Detalle día por día de lo que se paga en un rango (admin o el propio trabajador).
create or replace function public.detalle_pago(p_personal_id uuid, p_desde date, p_hasta date)
returns table (
  fecha            date,
  estado           text,
  hora_entrada     time,
  hora_salida      time,
  permiso_con_goce boolean,
  monto_dia        numeric,   -- monto registrado para ese día (null = sin registrar)
  monto            numeric,   -- lo que se paga ese día
  pagable          boolean,
  pagado           boolean
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_tarifa numeric;
begin
  if not (public.puede_administrar() or p_personal_id = public.mi_personal_id()) then
    raise exception 'Solo puedes consultar tus propios pagos';
  end if;
  if p_hasta < p_desde then
    raise exception 'La fecha final no puede ser anterior a la inicial';
  end if;
  select pago_por_dia into v_tarifa from public.personal where id = p_personal_id;

  return query
    select d.fecha,
           d.estado,
           d.hora_entrada,
           d.hora_salida,
           d.permiso_con_goce,
           a.monto_dia,
           case
             when d.estado in ('asistio','tardanza')               then coalesce(a.monto_dia, v_tarifa)
             when d.estado = 'permiso' and d.permiso_con_goce      then v_tarifa
             else 0::numeric
           end,
           (d.estado in ('asistio','tardanza') or (d.estado = 'permiso' and d.permiso_con_goce)),
           exists (select 1 from public.pagos pg
                    where pg.personal_id = p_personal_id and d.fecha between pg.fecha_desde and pg.fecha_hasta)
      from public.detalle_asistencia(p_desde, p_hasta, p_personal_id) d
      left join public.asistencias a on a.personal_id = p_personal_id and a.fecha = d.fecha
     order by d.fecha;
end;
$$;

-- Totales de un rango
create or replace function public.calcular_pago(p_personal_id uuid, p_desde date, p_hasta date)
returns table (
  dias_asistidos       integer,
  dias_permiso         integer,
  dias_permiso_pagado  integer,
  dias_falta           integer,
  tardanzas            integer,
  dias_sin_monto       integer,
  dias_ya_pagados      integer,
  monto_base           numeric
)
language sql stable security definer
set search_path = public
as $$
  select count(*) filter (where estado in ('asistio','tardanza'))::int,
         count(*) filter (where estado = 'permiso')::int,
         count(*) filter (where estado = 'permiso' and permiso_con_goce)::int,
         count(*) filter (where estado = 'falta')::int,
         count(*) filter (where estado = 'tardanza')::int,
         count(*) filter (where estado in ('asistio','tardanza') and monto_dia is null)::int,
         count(*) filter (where pagado)::int,
         coalesce(sum(monto), 0)
    from public.detalle_pago(p_personal_id, p_desde, p_hasta);
$$;

-- Lo que se le debe a cada trabajador: desde el día siguiente a su último pago hasta hoy.
create or replace function public.pagos_pendientes(p_personal_id uuid default null)
returns table (
  personal_id          uuid,
  dni                  text,
  nombres              text,
  apellidos            text,
  cargo                text,
  foto_rostro_url      text,
  foto_perfil_url      text,
  tipo_pago            text,
  pago_por_dia         numeric,
  ultimo_pago_hasta    date,
  ultimo_pago_fecha    date,
  desde                date,
  hasta                date,
  dias_asistidos       integer,
  dias_permiso_pagado  integer,
  dias_falta           integer,
  tardanzas            integer,
  dias_sin_monto       integer,
  monto_pendiente      numeric
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_admin boolean := public.puede_administrar();
  v_yo    uuid    := public.mi_personal_id();
begin
  if not v_admin and (p_personal_id is null or p_personal_id <> v_yo) then
    if v_yo is null then raise exception 'Sin acceso'; end if;
    p_personal_id := v_yo;
  end if;

  return query
    with base as (
      select p.*,
             (select max(pg.fecha_hasta) from public.pagos pg where pg.personal_id = p.id) as ult_hasta,
             (select pg.fecha_pago from public.pagos pg where pg.personal_id = p.id order by pg.fecha_hasta desc limit 1) as ult_fecha,
             (select min(a.fecha) from public.asistencias a where a.personal_id = p.id) as primera
        from public.personal p
       where p.estado = 'activo'
         and (p_personal_id is null or p.id = p_personal_id)
    ), rango as (
      select b.*,
             coalesce(b.ult_hasta + 1, greatest(b.fecha_ingreso, coalesce(b.primera, b.fecha_ingreso))) as r_desde,
             public.hoy_lima() as r_hasta
        from base b
    )
    select r.id, r.dni::text, r.nombres, r.apellidos, r.cargo, r.foto_rostro_url, r.foto_perfil_url,
           r.tipo_pago, r.pago_por_dia, r.ult_hasta, r.ult_fecha,
           r.r_desde, r.r_hasta,
           coalesce(c.dias_asistidos, 0), coalesce(c.dias_permiso_pagado, 0), coalesce(c.dias_falta, 0),
           coalesce(c.tardanzas, 0), coalesce(c.dias_sin_monto, 0), coalesce(c.monto_base, 0)
      from rango r
      -- Si ya se le pagó hasta hoy, el rango queda vacío (desde > hasta) y no hay nada pendiente.
      left join lateral (
        select * from public.calcular_pago(r.id, r.r_desde, greatest(r.r_desde, r.r_hasta))
      ) c on r.r_desde <= r.r_hasta
     order by r.apellidos, r.nombres;
end;
$$;

-- Guarda los montos por rendimiento de varios días: [{"fecha":"2026-11-03","monto":65}, ...]
-- monto null = volver al pago por día de referencia.
create or replace function public.fijar_montos_dia(p_personal_id uuid, p_montos jsonb)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_item  jsonb;
  v_fecha date;
  v_monto numeric;
  v_n     integer := 0;
begin
  if not public.puede_administrar() then
    raise exception 'Solo el administrador puede registrar montos';
  end if;
  for v_item in select * from jsonb_array_elements(coalesce(p_montos, '[]'::jsonb)) loop
    v_fecha := (v_item ->> 'fecha')::date;
    v_monto := nullif(v_item ->> 'monto', '')::numeric;
    if v_monto is not null and v_monto < 0 then
      raise exception 'El monto del % no puede ser negativo', to_char(v_fecha, 'DD/MM');
    end if;
    update public.asistencias
       set monto_dia = round(v_monto, 2)
     where personal_id = p_personal_id
       and fecha = v_fecha
       and estado in ('asistio','tardanza')
       and monto_dia is distinct from round(v_monto, 2);
    if found then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;

-- Registra un pago (ya entregado) por un rango de fechas.
create or replace function public.registrar_pago(
  p_personal_id      uuid,
  p_desde            date,
  p_hasta            date,
  p_metodo           text,
  p_bonos            numeric default 0,
  p_descuentos       numeric default 0,
  p_numero_operacion text    default null,
  p_observacion      text    default null
)
returns public.pagos
language plpgsql security definer
set search_path = public
as $$
declare
  c      record;
  v_pago public.pagos;
begin
  if not public.puede_administrar() then
    raise exception 'Solo el administrador puede registrar pagos';
  end if;
  if p_hasta < p_desde then
    raise exception 'La fecha final no puede ser anterior a la inicial';
  end if;
  if p_hasta > public.hoy_lima() then
    raise exception 'No se pueden pagar días que aún no llegan';
  end if;
  if p_metodo not in ('efectivo','yape','plin','transferencia','otro') then
    raise exception 'Método de pago no válido';
  end if;
  if coalesce(p_bonos, 0) < 0 or coalesce(p_descuentos, 0) < 0 then
    raise exception 'Bonos y descuentos deben ser 0 o más';
  end if;

  select * into c from public.calcular_pago(p_personal_id, p_desde, p_hasta);
  if c.dias_ya_pagados > 0 then
    raise exception 'Hay % día(s) de ese rango que ya fueron pagados. Elige fechas posteriores al último pago.', c.dias_ya_pagados;
  end if;

  insert into public.pagos (
    personal_id, periodo_mes, fecha_desde, fecha_hasta,
    dias_asistidos, dias_permiso, dias_permiso_pagado, dias_falta, tardanzas_acumuladas,
    pago_por_dia, monto_base, descuentos, bonos,
    estado_pago, fecha_pago, metodo_pago, numero_operacion, observacion, registrado_por
  )
  select p_personal_id, to_char(p_hasta, 'YYYY-MM'), p_desde, p_hasta,
         c.dias_asistidos, c.dias_permiso, c.dias_permiso_pagado, c.dias_falta, c.tardanzas,
         p.pago_por_dia, c.monto_base, coalesce(p_descuentos, 0), coalesce(p_bonos, 0),
         'pagado', public.hoy_lima(), p_metodo, nullif(trim(p_numero_operacion), ''), nullif(trim(p_observacion), ''),
         public.mi_personal_id()
    from public.personal p
   where p.id = p_personal_id
  returning * into v_pago;

  if v_pago.id is null then
    raise exception 'Trabajador no encontrado';
  end if;
  return v_pago;
end;
$$;

-- Cada usuario actualiza su propio perfil (teléfono, correo y foto).
create or replace function public.actualizar_mi_perfil(
  p_telefono        text default null,
  p_correo          text default null,
  p_foto_perfil_url text default null,
  p_quitar_foto     boolean default false
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_yo uuid := public.mi_personal_id();
begin
  if v_yo is null then
    raise exception 'Sin acceso';
  end if;
  if p_telefono is not null and p_telefono <> '' and p_telefono !~ '^[0-9+ ]{6,15}$' then
    raise exception 'Teléfono no válido';
  end if;
  if p_correo is not null and p_correo <> '' and p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Correo no válido';
  end if;
  if p_foto_perfil_url is not null and split_part(p_foto_perfil_url, '/', 1) <> v_yo::text then
    raise exception 'Ruta de foto no válida';
  end if;
  update public.personal
     set telefono        = case when p_telefono is null then telefono else nullif(trim(p_telefono), '') end,
         correo          = case when p_correo   is null then correo   else nullif(lower(trim(p_correo)), '') end,
         foto_perfil_url = case when p_quitar_foto then null else coalesce(p_foto_perfil_url, foto_perfil_url) end
   where id = v_yo;
end;
$$;

revoke execute on function public.detalle_pago(uuid, date, date)                                   from public, anon;
revoke execute on function public.calcular_pago(uuid, date, date)                                  from public, anon;
revoke execute on function public.pagos_pendientes(uuid)                                           from public, anon;
revoke execute on function public.fijar_montos_dia(uuid, jsonb)                                    from public, anon;
revoke execute on function public.registrar_pago(uuid, date, date, text, numeric, numeric, text, text) from public, anon;
revoke execute on function public.actualizar_mi_perfil(text, text, text, boolean)                  from public, anon;
grant  execute on function public.detalle_pago(uuid, date, date)                                   to authenticated, service_role;
grant  execute on function public.calcular_pago(uuid, date, date)                                  to authenticated, service_role;
grant  execute on function public.pagos_pendientes(uuid)                                           to authenticated, service_role;
grant  execute on function public.fijar_montos_dia(uuid, jsonb)                                    to authenticated, service_role;
grant  execute on function public.registrar_pago(uuid, date, date, text, numeric, numeric, text, text) to authenticated, service_role;
grant  execute on function public.actualizar_mi_perfil(text, text, text, boolean)                  to authenticated, service_role;

-- =====================================================================
-- Storage: fotos de perfil (privado)
--   fotos_perfil/<personal_id>/perfil.jpg
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos_perfil', 'fotos_perfil', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chahua_perfil_ver     on storage.objects;
drop policy if exists chahua_perfil_subir   on storage.objects;
drop policy if exists chahua_perfil_cambiar on storage.objects;
drop policy if exists chahua_perfil_borrar  on storage.objects;

-- Todos los usuarios del sistema ven las fotos de perfil (avatares)
create policy chahua_perfil_ver on storage.objects
  for select to authenticated
  using (bucket_id = 'fotos_perfil');
-- Cada uno sube, cambia o borra solo su carpeta (el admin, cualquiera)
create policy chahua_perfil_subir on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fotos_perfil'
              and ((storage.foldername(name))[1] = (select public.mi_personal_id())::text or (select public.es_admin())));
create policy chahua_perfil_cambiar on storage.objects
  for update to authenticated
  using      (bucket_id = 'fotos_perfil'
              and ((storage.foldername(name))[1] = (select public.mi_personal_id())::text or (select public.es_admin())))
  with check (bucket_id = 'fotos_perfil'
              and ((storage.foldername(name))[1] = (select public.mi_personal_id())::text or (select public.es_admin())));
create policy chahua_perfil_borrar on storage.objects
  for delete to authenticated
  using (bucket_id = 'fotos_perfil'
         and ((storage.foldername(name))[1] = (select public.mi_personal_id())::text or (select public.es_admin())));

-- =====================================================================
-- Datos de ejemplo: José (mecánico) cobra por rendimiento
-- =====================================================================
update public.personal set tipo_pago = 'variable' where dni = '70984512';

update public.asistencias a
   set monto_dia = case extract(isodow from a.fecha)::int
                     when 1 then 70 when 2 then 82 when 3 then 75 when 4 then 90 when 5 then 68 else 85
                   end
  from public.personal p
 where p.id = a.personal_id
   and p.dni = '70984512'
   and a.estado in ('asistio','tardanza')
   and a.fecha >= date '2026-11-01'
   and a.monto_dia is null
   and not exists (select 1 from public.pagos pg where pg.personal_id = a.personal_id and a.fecha between pg.fecha_desde and pg.fecha_hasta);

-- Lucía cobra por semana: pago de la primera semana de noviembre por Yape
select public.registrar_pago(
  (select id from public.personal where dni = '71239845'),
  date '2026-11-01', date '2026-11-07', 'yape', 0, 0, '00482917', 'Pago acumulado hasta el sábado 7'
)
where not exists (
  select 1 from public.pagos pg join public.personal p on p.id = pg.personal_id
   where p.dni = '71239845' and pg.fecha_hasta >= date '2026-11-07'
);

-- =====================================================================
-- Base de conocimiento del asistente: nuevas reglas de pago
-- =====================================================================
update public.conocimiento_empresa
   set respuesta_politica = 'No. Las tardanzas no generan descuento en el pago. Se registran y se acumulan en el historial de asistencia como control.'
 where pregunta_frecuente = '¿Las tardanzas tienen descuento?';
update public.conocimiento_empresa
   set respuesta_politica = 'Por defecto, los días de permiso no se pagan. El administrador puede decidir pagar un permiso en particular (permiso con goce); en ese caso esos días se suman a lo que tienes por cobrar.'
 where pregunta_frecuente = '¿Los días de permiso se pagan?';
update public.conocimiento_empresa
   set pregunta_frecuente = '¿Cómo se calcula mi pago?',
       respuesta_politica = 'Se suma lo que ganaste cada día asistido más los días de permiso con goce, más bonos y menos descuentos. Si tu pago es fijo, cada día vale tu pago por día; si es por rendimiento, el administrador registra el monto de cada día según tu trabajo. Los días con tardanza cuentan como asistidos. Las faltas y los permisos sin goce no se pagan.'
 where pregunta_frecuente in ('¿Cómo se calcula mi pago del mes?', '¿Cómo se calcula mi pago?');
update public.conocimiento_empresa
   set respuesta_politica = 'En el módulo de Pagos de la app o de la web verás lo que tienes por cobrar desde tu último pago y la lista de pagos recibidos con su fecha, periodo, monto y método (efectivo, Yape, Plin o transferencia). Puedes descargar el comprobante en PDF o preguntarle al asistente.'
 where pregunta_frecuente = '¿Cómo sé si ya me pagaron?';
insert into public.conocimiento_empresa (categoria, pregunta_frecuente, respuesta_politica)
select 'Pagos', '¿Cada cuánto me pagan?', 'Puedes cobrar cuando lo necesites: por semana, por quincena, por mes o por días. Pídeselo al administrador; él registra el pago por el rango de días trabajados desde tu último pago y elige el método (efectivo, Yape, Plin o transferencia).'
where not exists (select 1 from public.conocimiento_empresa where pregunta_frecuente = '¿Cada cuánto me pagan?');
