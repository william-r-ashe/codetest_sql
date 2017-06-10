-- Aledade SQL code test
--
-- edit this file to answer the questions below.
-- send back the entire file, such that it can be run against a PostgreSQL 9.5+ database in the following way to produce results:
-- psql -h foohost < test.sql

begin;

create temporary table person (
    id            serial primary key,
    name          text not null,
    deceased_date date
) on commit drop;

-- association of a person with an address over a timespan
-- if thru_dt is NULL, consider "current"
create temporary table person_address (
    id        serial primary key,
    person_id integer not null references person (id),
    address   text    not null,
    from_dt   date    not null,
    thru_dt   date check (thru_dt >= from_dt or thru_dt is null)
) on commit drop;

insert into person (id, name, deceased_date)
values
    (1, 'Richard Harris', '2002-10-25'::date)
  , (2, 'Maggie Smith',    null)
  , (3, 'Robbie Coltrane', null)
  , (4, 'Vernon Dursley',  null)
  ;

insert into person_address (person_id, address, from_dt, thru_dt)
values
    (1, '100 Main St',         '1989-01-01'::date, '1995-01-01'::date)
  , (1, '5322 Otter Ln',       '1992-01-01'::date, '2002-10-25'::date)
  , (2, '34 Lighthouse Ave',   '1979-01-01'::date, '2007-01-01'::date)
  , (2, '904 Chesterfield St', '2010-01-01'::date, '2016-01-01'::date)
  , (2, '19 Chatham Ave',      '2015-01-01'::date, null)
  , (3, '6 Pearl St',          '1979-01-01'::date, '2001-01-01'::date)
  , (3, '456 Addison Rd',      '2003-01-01'::date, '2003-01-01'::date)
  , (3, '62 Adler St',         '2005-01-01'::date, '2010-12-01'::date)
  , (3, '234 Elizabeth St',    '2011-01-01'::date, null)
  , (4, '4 Privet Drive',      '1994-01-01'::date, null)
  ;

-- TODO 1. list living persons and all person_addresses associated with them on June 5, 2017

-- "on June 5, 2017" seems to imply any address(es) they had on that day specifically:
select p.id, p.name, a.address
from person p
  inner join person_address a
    on a.person_id = p.id
where p.deceased_date is null
  and '2017-06-05'::date between a.from_dt and coalesce(a.thru_dt, now())
order by p.id;

-- but if "all person_addresses" meant every address that had up to that point:
select p.id, p.name, a.address
from person p
  inner join person_address a
    on a.person_id = p.id
where p.deceased_date is null
  and (a.thru_dt <= '2017-06-05'::date or a.thru_dt is null)
order by p.id, a.from_dt;


-- TODO 2. list top 3 person_address records per person order by longest duration
-- (null thru_dt should be considered todays date, and should be included in consideration)

select id, name, address, duration_in_days
from (
  select p.id, p.name, a.address,
    row_number() over (partition by p.id order by
          date_part('day', coalesce(a.thru_dt, now()) - a.from_dt) desc) as row,
    date_part('day', coalesce(a.thru_dt, now()) - a.from_dt) as duration_in_days
    from person p
    inner join person_address a
      on a.person_id = p.id
) dur
where row <= 3
order by id, duration_in_days desc;


-- Given a third table person_address_current (created below), intended to contain a non-deceased person's "current" address
-- person_address_current is intended to be kept up-to-date every day, but due to an error hasn't been updated since 2001-01-01.
-- TODO 3. Write SQL to get person_address_current's data up-to-date
-- a. update/insert living person's address to be current as of June 5, 2017.
-- b. remove deceased persons from the table
-- c. records that have not changed since 2001-01-01 should not change

create temporary table person_address_current (
  id        serial primary key,
  person_id integer not null references person (id),
  address   text    not null,
  from_dt   date    not null
) on commit drop;

insert into person_address_current (person_id, address, from_dt)
  select
    p.id
    , pa.address
    , pa.from_dt
  from person_address pa
  join person p
    on p.id = pa.person_id and (p.deceased_date >= '2001-01-01'::date or p.deceased_date is null)
  where from_dt <= '2001-01-01'::date and (thru_dt >= '2001-01-01'::date or thru_dt is null);


-- a. update/insert living person's address to be current as of June 5, 2017.

update person_address_current c
set address = a.address,
  from_dt = a.from_dt
from person p
  inner join person_address a
    on a.person_id = p.id
where c.person_id = p.id
  and p.deceased_date is null
  and a.thru_dt is null

  -- c. records that have not changed since 2001-01-01 should not change
  and a.from_dt > '2001-01-01'::date
  ;

insert into person_address_current (person_id, address, from_dt)
select p.id, a.address, a.from_dt
from person p
  inner join person_address a
    on a.person_id = p.id
  left outer join person_address_current c
    on c.person_id = p.id
    and c.address = a.address
    and c.from_dt = a.from_dt
where p.deceased_date is null
  and a.thru_dt is null
  and c.id is null;


/*
NOTE: Based on the description of the purpose of the table and the fact
      that this code was committed on 6/5, I made the assumption that
      "current as of June 5, 2017" was intended to mean bring the table
      completely up to date. However, if the intention was to bring it forward
      to June 5, 2017 and ignore any further changes after that, I would
      accomplish that with the adjustment below:

In both queries, replace:

    and a.thru_dt is null

with:

    and (a.thru_dt >= '2017-06-05'::date or a.thru_dt is null)
    and not exists (
          select 1
          from person_address earlier_changes
          where earlier_changes.person_id = a.person_id
            and (earlier_changes.thru_dt >= '2017-06-05'::date
                  or earlier_changes.thru_dt is null)
            and earlier_changes.thru_dt < coalesce(a.thru_dt, now())
        )

 */



-- b. remove deceased persons from the table

delete from person_address_current
using person p
where person_id = p.id
  and p.deceased_date is not null;



-- Pull all records in person_address_current to show final results
select *
from person_address_current
order by id;


commit;
