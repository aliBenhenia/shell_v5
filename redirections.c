/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   redirections.c                                     :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/10 23:47:23 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/13 14:59:11 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

int is_last(t_redirections **redirections)
{
    t_redirections  *curr;

    if (!*redirections)
        return (1);
    curr = *redirections;
    while (curr)
    {
        if (curr->type == RIGHTRED || curr->type == APPEND)
            return (0);
        curr = curr->next;
    }
    return (1);
}

t_redirections  *last_outfile(t_cmd_line **cmd_line)
{
    t_redirections  *curr;
    int             fd;

    curr = (*cmd_line)->redirections;
    while (curr)
    {
        if (curr->type == RIGHTRED || curr->type == APPEND)
        {
            fd = open(curr->file, O_CREAT | O_RDWR, 0664);
            if (is_last(&curr->next))
                return (curr);
        }
        curr = curr->next;
    }
    return (NULL);
}

int is_last_infile(t_redirections **redirections)
{
    t_redirections  *curr;

    if (!*redirections)
        return (1);
    curr = *redirections;
    while (curr)
    {
        if (curr->type == LEFTRED || curr->type == HEREDOC)
            return (0);
        curr = curr->next;
    }
    return (1);
}

t_redirections  *last_infile(t_cmd_line **cmd_line, int *no_file)
{
    t_redirections  *curr;
    int fd;

    curr = (*cmd_line)->redirections;
    while (curr)
    {
        if (curr->type == RIGHTRED || curr->type == APPEND)
            fd = open(curr->file, O_CREAT | O_RDWR, 0664);
        if (curr->type == LEFTRED || curr->type == HEREDOC)
        {
            if (curr->type == LEFTRED)
            {
                fd = open(curr->file, O_RDONLY, 0777);
                if (fd == -1)
                {
                    write(2, "minishell: ", 12);
                    write(2, curr->file, ft_strlen(curr->file));
                    write(2, ": No such file or directory\n", 28);
                    *no_file = 0;
                    return (NULL);
                }
            }
            if (is_last_infile(&curr->next))
                return (curr);
        }
        curr = curr->next;
    }
    return (NULL);
}