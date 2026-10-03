-- =====================================================================
--  Coup de Banquise : pseudo, compte anonyme et classement
-- =====================================================================
-- À coller une fois dans l'éditeur SQL de Supabase (SQL Editor › New query › Run).
-- Le script peut être relancé sans dégât : il ne supprime aucune donnée.
--
-- Avant : Authentication › Sign In / Providers › activer « Allow anonymous sign-ins ».
--
-- Principe : les deux tables sont lisibles par tout le monde, mais personne n'y écrit
-- directement. Toutes les écritures passent par les fonctions ci-dessous, qui ne touchent
-- que les lignes du joueur connecté. C'est ce qui permet au serveur de choisir lui-même
-- la semaine et de refuser un score qui ne bat pas le précédent.

-- ---------- Tables ----------
create table if not exists public.joueurs (
  id      uuid primary key references auth.users (id) on delete cascade,
  pseudo  text not null,
  cree_le timestamptz not null default now(),
  constraint joueurs_pseudo_longueur check (char_length(pseudo) between 3 and 16),
  constraint joueurs_pseudo_propre check (pseudo = btrim(pseudo) and pseudo !~ '[[:cntrl:]<>]' and pseudo !~ '\s\s')
);
-- pseudo unique sans tenir compte des majuscules : « Momo » et « momo » sont le même
create unique index if not exists joueurs_pseudo_unique on public.joueurs (lower(pseudo));

-- une seule ligne par joueur et par période ; la période vaut 'general' ou la semaine ('2026-S40')
create table if not exists public.meilleurs_scores (
  joueur   uuid not null references public.joueurs (id) on delete cascade,
  periode  text not null,
  distance numeric(8, 1) not null check (distance > 0),
  maj_le   timestamptz not null default now(),
  primary key (joueur, periode)
);
create index if not exists meilleurs_scores_classement on public.meilleurs_scores (periode, distance desc, maj_le);

-- ---------- Droits : tout le monde lit, personne n'écrit en direct ----------
alter table public.joueurs enable row level security;
alter table public.meilleurs_scores enable row level security;

drop policy if exists "lecture pour tous" on public.joueurs;
create policy "lecture pour tous" on public.joueurs for select to anon, authenticated using (true);
drop policy if exists "lecture pour tous" on public.meilleurs_scores;
create policy "lecture pour tous" on public.meilleurs_scores for select to anon, authenticated using (true);

revoke all on public.joueurs, public.meilleurs_scores from anon, authenticated;
grant select on public.joueurs, public.meilleurs_scores to anon, authenticated;

-- ---------- Semaine : du lundi 0 h au dimanche minuit, heure de Paris ----------
create or replace function public.semaine_de(p_instant timestamptz)
returns text language sql stable set search_path = '' as $$
  select to_char(p_instant at time zone 'Europe/Paris', 'IYYY"-S"IW');
$$;

-- secondes restantes avant le prochain lundi 0 h (heure de Paris)
create or replace function public.reste_semaine()
returns integer language sql stable set search_path = '' as $$
  select ceil(extract(epoch from
    ((date_trunc('week', now() at time zone 'Europe/Paris') + interval '7 days') at time zone 'Europe/Paris') - now()))::integer;
$$;

-- ---------- Pseudo : 3 à 16 caractères, unique, modifiable ----------
-- Renvoie { ok: true, pseudo } ou { ok: false, raison: 'pris' | 'invalide' }.
create or replace function public.definir_pseudo(p_pseudo text)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_moi uuid := auth.uid();
  v_pseudo text := btrim(regexp_replace(coalesce(p_pseudo, ''), '\s+', ' ', 'g'));
begin
  if v_moi is null then raise exception 'non connecté' using errcode = '28000'; end if;
  if char_length(v_pseudo) not between 3 and 16 or v_pseudo ~ '[[:cntrl:]<>]' then
    return json_build_object('ok', false, 'raison', 'invalide');
  end if;
  begin
    insert into public.joueurs (id, pseudo) values (v_moi, v_pseudo)
    on conflict (id) do update set pseudo = excluded.pseudo;
  exception when unique_violation then
    return json_build_object('ok', false, 'raison', 'pris');
  end;
  return json_build_object('ok', true, 'pseudo', v_pseudo);
end $$;

-- ---------- Envoi d'un score ----------
-- Le score n'est enregistré que s'il bat le précédent, pour le classement général et pour
-- celui de la semaine en cours. p_age_s = ancienneté du lancer en secondes (0 s'il vient
-- d'avoir lieu) : un lancer fait hors ligne la semaine dernière ne compte que pour le général.
create or replace function public.envoyer_score(p_distance numeric, p_age_s integer default 0)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_moi uuid := auth.uid();
  v_d numeric(8, 1);
  v_sem text := public.semaine_de(now());
  v_hebdo boolean;
  v_gen numeric; v_heb numeric; v_rg integer; v_rh integer;
begin
  if v_moi is null then raise exception 'non connecté' using errcode = '28000'; end if;
  if p_distance is null or p_distance < 0.05 or p_distance >= 1000000 then
    raise exception 'distance invalide' using errcode = '22023';
  end if;
  if not exists (select 1 from public.joueurs where id = v_moi) then
    raise exception 'pseudo manquant' using errcode = 'P0002';
  end if;
  v_d := round(p_distance, 1);
  v_hebdo := public.semaine_de(now() - make_interval(secs => greatest(coalesce(p_age_s, 0), 0))) = v_sem;

  insert into public.meilleurs_scores as s (joueur, periode, distance) values (v_moi, 'general', v_d)
  on conflict (joueur, periode) do update set distance = excluded.distance, maj_le = now()
  where excluded.distance > s.distance;
  if v_hebdo then
    insert into public.meilleurs_scores as s (joueur, periode, distance) values (v_moi, v_sem, v_d)
    on conflict (joueur, periode) do update set distance = excluded.distance, maj_le = now()
    where excluded.distance > s.distance;
  end if;

  select distance into v_gen from public.meilleurs_scores where joueur = v_moi and periode = 'general';
  select distance into v_heb from public.meilleurs_scores where joueur = v_moi and periode = v_sem;
  select count(*) + 1 into v_rg from public.meilleurs_scores where periode = 'general' and distance > v_gen;
  if v_heb is not null then
    select count(*) + 1 into v_rh from public.meilleurs_scores where periode = v_sem and distance > v_heb;
  end if;
  return json_build_object('semaine', v_sem, 'reste_s', public.reste_semaine(),
    'general', v_gen, 'hebdo', v_heb, 'rang_general', v_rg, 'rang_hebdo', v_rh);
end $$;

-- ---------- Lecture du classement : top 10, plus le joueur et ses deux voisins ----------
-- p_periode = 'semaine' (semaine en cours, choisie par le serveur) ou 'general'.
-- À égalité, le premier arrivé reste devant.
create or replace function public.classement(p_periode text default 'semaine')
returns json language sql stable set search_path = '' as $$
  with p as (
    select case when p_periode = 'general' then 'general' else public.semaine_de(now()) end as periode
  ), r as (
    select s.joueur, j.pseudo, s.distance,
           row_number() over (order by s.distance desc, s.maj_le, j.cree_le) as rang
    from public.meilleurs_scores s
    join public.joueurs j on j.id = s.joueur
    where s.periode = (select periode from p)
  ), m as (
    select rang from r where joueur = auth.uid()
  )
  select json_build_object(
    'periode', (select periode from p),
    'reste_s', public.reste_semaine(),
    'total', (select count(*) from r),
    'lignes', coalesce((
      select json_agg(json_build_object('rang', r.rang, 'pseudo', r.pseudo, 'distance', r.distance,
                                        'moi', coalesce(r.joueur = auth.uid(), false)) order by r.rang)
      from r
      where r.rang <= 10 or r.rang between (select rang from m) - 1 and (select rang from m) + 1
    ), '[]'::json));
$$;

-- ---------- Suppression : « Supprimer mon pseudo et mes scores » ----------
-- Supprime le compte anonyme ; le pseudo et les scores partent avec lui (suppression en cascade).
create or replace function public.supprimer_mon_compte()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'non connecté' using errcode = '28000'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- ---------- Qui peut appeler quoi ----------
revoke execute on function public.semaine_de(timestamptz), public.reste_semaine(), public.definir_pseudo(text),
  public.envoyer_score(numeric, integer), public.classement(text), public.supprimer_mon_compte() from public, anon, authenticated;
grant execute on function public.semaine_de(timestamptz), public.reste_semaine(), public.classement(text) to anon, authenticated;
grant execute on function public.definir_pseudo(text), public.envoyer_score(numeric, integer), public.supprimer_mon_compte() to authenticated;

-- ---------- Entretien, à la main depuis l'éditeur SQL ----------
-- Retirer un score inventé :
--   delete from public.meilleurs_scores where joueur = (select id from public.joueurs where lower(pseudo) = lower('LePseudo'));
-- Retirer un joueur, son pseudo et tous ses scores :
--   delete from auth.users where id = (select id from public.joueurs where lower(pseudo) = lower('LePseudo'));
-- Nettoyer les comptes anonymes créés il y a plus de 30 jours et restés sans pseudo :
--   delete from auth.users u where u.is_anonymous and u.created_at < now() - interval '30 days'
--     and not exists (select 1 from public.joueurs j where j.id = u.id);
