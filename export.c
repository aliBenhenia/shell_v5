#include "minishell.h"
t_export	*addnew(char *var, char *value)
{
	t_export	*new;

	new = malloc(sizeof(t_export));
	if (!new)
		return (NULL);
	new->var = var;
	new->value = value;
	new->next = NULL;
	return (new);
}
void	addback_export(t_export **a, t_export *new)
{
  t_export  *head;
	if((*a) == NULL)
	{
		(*a) = new;
	}
	else
	{
		head = (*a);
		new->next = NULL;
		head = (*a);
		while (head->next)
			head = head->next;
		head->next = new;
	}
}

t_env_list	*addnew2(char *var, char *value)
{
	t_env_list	*new;

	new = malloc(sizeof(t_env_list));
	if (!new)
		return (NULL);
	new->name = var;
	new->value = value;
	new->next = NULL;
	return (new);
}
void	addback_env(t_env_list **a, t_env_list *new)
{
  t_env_list  *head;

	new->next = NULL;
	head = (*a);
	if(head == NULL)
	{
		 (*a) = new;
	}
	else
	{ 
		head = (*a);
		while (head->next)
			head = head->next;
		head->next = new;
	}
}
void    do_env(char *env[])
{
	int i;

	i = 0;
	while (env[i])
	{
		ft_putstr(env[i]);
		ft_putstr("\n");
		i++;
	}
}



int check_if_equal_is(char *str)
{
	int i;

	i = 0;
	while (str[i])
	{
		if (str[i] == '=' && str[i + 1])
		{
			return (1);
		}
		i++;
	}
	return (0);
}
int check_if_in_env(char *name,char *value, t_export *env)
{
	t_export *head;

	head = env;
	while (head)
	{
		if (ft_strcmp(head->var,name) == 0)
		{
			return (1);
		}
		head = head->next;
	}
	return (0);
}
char *get_name(char *s)
{
	int i;
	char *p;

	i = 0;
	if(s[0] == '=')
		return (NULL);
	while (s[i] && s[i] != '=')
	{
		if(s[i] == '+' && s[i + 1] == '=' && i > 2)
			break;
		i++;
	}
	p = malloc(i + 1);
	i = 0;
	while (s[i] && s[i]  != '=')
	{
		p[i] = s[i];
		if(s[i] == '+' && s[i + 1] == '=' && i > 2)
			break;
		i++;
	}
	p[i] = '\0';
	return (p);
}
char *get_value(char *s)
{
	int i;
	int j;
	int f;
	char *p;

	i = 0;
	f = 0;
	while (s[i] != '=')
		i++;
	i++;
	j = i;
	while (s[i++])
		f++;
	p = malloc(f + 1);
	i = 0;
	while (s[j])
		p[i++] = s[j++];
	p[i] = '\0';
	return (p);
}
void	edit_value(char *name, char *value, t_export **data,t_env_list **env_list)
{
	t_export *head;
	t_env_list *lst;

	head = (*data);
	lst = (*env_list);
	while (head)
	{
		if (ft_strcmp(head->var,name) == 0)
		{
			head->value = NULL;
			head->value = value;
			return ;
		}
		head = head->next;
	}
	while (lst)
	{printf("home --------------------------------------------------------> \n");
		if (ft_strcmp(lst->name,name) == 0)
		{
			lst->value = NULL;
			lst->value = value;
			return ;
		}
		lst = lst->next;
	}
}
int	check_append(char *s)
{
	int	i;

	i = 0;
	while (s[i])
	{
		if(s[i] == '+' && s[i + 1] == '=')
		{
			return 1;
		}
		i++;
	}
	return (0);
}
void	append_string(char *name, char *value,t_export **data)
{
	int	i;
	t_export *head;

	head = (*data);
	while (head)
	{
		if (ft_strcmp(head->var, name) == 0)
		{
			head->value = ft_strjoin(head->value,value);
			return;
		}
		head = head->next;
	}
}

void	error_od_export(char *s)
{
	printf("error : %s not identifier\n",s);
}
int correct_name(char *s)
{
	int	i;

	i = 0;
	if (s == NULL)
		return (0);
	while (s[i])
	{
		if(ft_isalnum(s[i]) == 0) // check correct name 
		{
			if(s[i] == '+' && s[i + 1] == '\0' && i != 0) // for append in last 
				return (1);
			return (0);
		}
		i++;
	}
	return (1);
}
int	eqaul_last_only(char *s)
{
	int 	i;

	i = 0;
	while (s[i])
	{
		if(s[i] == '=' && s[i + 1])
			return 0;
		if(s[i] == '=' && s[i + 1] == '\0')
		{
			return(1);
		}
		i++;
	}
	return(0);
}
void    add_var_in_list(t_export **data,t_env_list **env_list, char *str)
{
	char    **var = malloc(sizeof(char *) * 3);
	t_env_list *variable;
	t_export *variable1;

	if (check_if_equal_is(str) && eqaul_last_only(str) == 0)
	{
		var[0] = get_name(str);
		var[1] = get_value(str);
		if(check_if_in_env(var[0],var[1],*data)) 
		{
				if(check_append(str))
				{
					append_string(var[0],var[1],data);
					return;
				}
				edit_value(var[0], var[1],data,env_list);
				return ;
		}
		variable1 = addnew(var[0],var[1]);
		addback_export(data,variable1);
		variable = addnew2(var[0],var[1]);
		addback_env(env_list,variable);
	}
	else
	{
		var[0] = get_name(str);
		if(eqaul_last_only(str))
		{
			var[0] = ft_strjoin(var[0],"=");
			variable = addnew2(var[0],"");
			addback_env(env_list,variable);
		}
		variable1 = addnew(var[0],"\0");
		addback_export(data,variable1);
	}
}

void    do_export(char *str[],t_export **data, t_env_list **env_list)
{
	int i;
	int j;
	char *temp;

	i = 1;
	j = 0;
	if (str[1] == NULL)
	{
		t_export *head = (*data);
		while (head)
		{
			if(*(head->value) == '\0')
			{
				if(eqaul_last_only(head->var))
					printf("declare -x %s\"\"\n",head->var);
				else
					printf("declare -x %s\n",head->var);
			}
			else
				 printf("declare -x %s=\"%s\"\n",head->var,head->value);
			head = head->next;
		}
	}
	while (str[i])
	{
		if(correct_name(get_name(str[i])) && !isdigit(str[i][0]))
			  add_var_in_list(data,env_list, str[i]);
		else
			error_od_export(str[i]);
		i++;
	}
	 sort(data);
}